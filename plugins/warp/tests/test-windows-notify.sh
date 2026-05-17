#!/bin/bash
# Tests for the Windows notification fallback scripts.
#
# Validates win-notify.sh deduplication, event routing, and integration
# with the existing hook scripts on Windows.
#
# Usage: ./tests/test-windows-notify.sh
#
# These tests work on any platform — they mock WINDIR and powershell
# to verify logic without actually sending notifications.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASSED=0
FAILED=0

# --- Test helpers ---

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✓ $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ $test_name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAILED=$((FAILED + 1))
    fi
}

# Create a mock powershell that logs calls instead of sending toasts
MOCK_DIR=$(mktemp -d)
MOCK_LOG="$MOCK_DIR/powershell-calls.log"
cat > "$MOCK_DIR/powershell" << 'MOCK_EOF'
#!/bin/bash
echo "$@" >> "$(dirname "$0")/powershell-calls.log"
MOCK_EOF
chmod +x "$MOCK_DIR/powershell"

# Clean up on exit
cleanup() {
    rm -rf "$MOCK_DIR"
    rmdir /tmp/warp-notify-lock 2>/dev/null || true
}
trap cleanup EXIT

echo "=== win-notify.sh ==="

# --- Test: exits on non-Windows ---

echo ""
echo "--- Non-Windows exit ---"
unset WINDIR
echo '{}' | bash "$SCRIPT_DIR/win-notify.sh" "stop" '{}' 2>/dev/null
assert_eq "exits silently on non-Windows" "0" "$?"

# --- Test: runs on Windows (mocked) ---

echo ""
echo "--- Windows detection ---"
export WINDIR="C:\\Windows"
export PATH="$MOCK_DIR:$PATH"
# Clean any stale lock
rmdir /tmp/warp-notify-lock 2>/dev/null || true
> "$MOCK_LOG"

bash "$SCRIPT_DIR/win-notify.sh" "stop" '{"cwd":"/tmp/my-project"}' 2>/dev/null
sleep 0.5
assert_eq "powershell was called" "true" "$([ -s "$MOCK_LOG" ] && echo true || echo false)"

# Check the powershell args contain the title
CALL=$(cat "$MOCK_LOG" 2>/dev/null)
if echo "$CALL" | grep -q "Task Completed"; then
    echo "  ✓ stop event produces 'Task Completed' title"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ stop event produces 'Task Completed' title"
    echo "    actual call: $CALL"
    FAILED=$((FAILED + 1))
fi

# --- Test: deduplication ---

echo ""
echo "--- Deduplication ---"
# Lock should still exist from the previous call
> "$MOCK_LOG"
bash "$SCRIPT_DIR/win-notify.sh" "stop" '{"cwd":"/tmp/test"}' 2>/dev/null
sleep 0.5
assert_eq "second call within 8s is skipped" "false" "$([ -s "$MOCK_LOG" ] && echo true || echo false)"

# Clean lock and verify next call goes through
rmdir /tmp/warp-notify-lock 2>/dev/null || true
> "$MOCK_LOG"
bash "$SCRIPT_DIR/win-notify.sh" "stop" '{"cwd":"/tmp/test"}' 2>/dev/null
sleep 0.5
assert_eq "call after lock cleared goes through" "true" "$([ -s "$MOCK_LOG" ] && echo true || echo false)"

# --- Test: event types ---

echo ""
echo "--- Event type routing ---"

# idle_prompt
rmdir /tmp/warp-notify-lock 2>/dev/null || true
> "$MOCK_LOG"
bash "$SCRIPT_DIR/win-notify.sh" "idle_prompt" '{"cwd":"/tmp/proj"}' 2>/dev/null
sleep 0.5
CALL=$(cat "$MOCK_LOG" 2>/dev/null)
if echo "$CALL" | grep -q "Input Needed"; then
    echo "  ✓ idle_prompt produces 'Input Needed' title"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ idle_prompt produces 'Input Needed' title"
    echo "    actual: $CALL"
    FAILED=$((FAILED + 1))
fi

# permission_request
rmdir /tmp/warp-notify-lock 2>/dev/null || true
> "$MOCK_LOG"
bash "$SCRIPT_DIR/win-notify.sh" "permission_request" '{"cwd":"/tmp/proj","tool_name":"Bash"}' 2>/dev/null
sleep 0.5
CALL=$(cat "$MOCK_LOG" 2>/dev/null)
if echo "$CALL" | grep -q "Permission Required"; then
    echo "  ✓ permission_request produces 'Permission Required' title"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ permission_request produces 'Permission Required' title"
    echo "    actual: $CALL"
    FAILED=$((FAILED + 1))
fi

# session_start (should be skipped)
rmdir /tmp/warp-notify-lock 2>/dev/null || true
> "$MOCK_LOG"
bash "$SCRIPT_DIR/win-notify.sh" "session_start" '{"cwd":"/tmp/proj"}' 2>/dev/null
sleep 0.5
assert_eq "session_start is silently skipped" "false" "$([ -s "$MOCK_LOG" ] && echo true || echo false)"

# --- Test: project name extraction ---

echo ""
echo "--- Project name in title ---"
rmdir /tmp/warp-notify-lock 2>/dev/null || true
> "$MOCK_LOG"
bash "$SCRIPT_DIR/win-notify.sh" "stop" '{"cwd":"/home/user/awesome-project"}' 2>/dev/null
sleep 0.5
CALL=$(cat "$MOCK_LOG" 2>/dev/null)
if echo "$CALL" | grep -q "awesome-project"; then
    echo "  ✓ project name extracted from cwd"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ project name extracted from cwd"
    echo "    actual: $CALL"
    FAILED=$((FAILED + 1))
fi

# --- Test: hook scripts include win-notify.sh call ---

echo ""
echo "--- Hook scripts patched ---"

for HOOK in on-stop.sh on-notification.sh on-permission-request.sh; do
    if grep -q "win-notify.sh" "$SCRIPT_DIR/$HOOK" 2>/dev/null; then
        echo "  ✓ $HOOK calls win-notify.sh"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ $HOOK missing win-notify.sh call"
        FAILED=$((FAILED + 1))
    fi
done

# --- Test: warp-notify.sh fallback logic ---

echo ""
echo "--- warp-notify.sh /dev/tty fallback ---"

if grep -q "exit 0" "$SCRIPT_DIR/warp-notify.sh" && grep -q '>&2' "$SCRIPT_DIR/warp-notify.sh"; then
    echo "  ✓ warp-notify.sh has /dev/tty → stderr fallback"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ warp-notify.sh missing fallback logic"
    FAILED=$((FAILED + 1))
fi

# --- Test: win-toast.ps1 exists and has correct structure ---

echo ""
echo "--- win-toast.ps1 structure ---"

if [ -f "$SCRIPT_DIR/win-toast.ps1" ]; then
    echo "  ✓ win-toast.ps1 exists"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ win-toast.ps1 missing"
    FAILED=$((FAILED + 1))
fi

if grep -q "dev.warp.Warp" "$SCRIPT_DIR/win-toast.ps1" 2>/dev/null; then
    echo "  ✓ win-toast.ps1 uses Warp AppUserModelId"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ win-toast.ps1 missing Warp AppUserModelId"
    FAILED=$((FAILED + 1))
fi

if grep -q "ToastNotificationManager" "$SCRIPT_DIR/win-toast.ps1" 2>/dev/null; then
    echo "  ✓ win-toast.ps1 uses Windows.UI.Notifications API"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ win-toast.ps1 missing ToastNotificationManager"
    FAILED=$((FAILED + 1))
fi

# Clean up env
unset WINDIR

# --- Summary ---

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
