#!/bin/bash

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$PLUGIN_ROOT/scripts"

PASSED=0
FAILED=0

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

assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    if printf '%s' "$haystack" | grep -Fq "$needle"; then
        echo "  ✓ $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ $test_name"
        echo "    expected to find: $needle"
        echo "    actual:           $haystack"
        FAILED=$((FAILED + 1))
    fi
}

assert_json_field() {
    local test_name="$1"
    local json="$2"
    local field="$3"
    local expected="$4"
    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
    assert_eq "$test_name" "$expected" "$actual"
}

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

FAKE_OZ="$TEST_TMP/fake-oz.sh"
FAKE_OZ_LOG="$TEST_TMP/fake-oz.log"
FAKE_OZ_WATCH="$TEST_TMP/watch.ndjson"
STATE_ROOT="$TEST_TMP/state"
HOOK_INPUT='{"session_id":"sess-123","cwd":"/tmp/project"}'
STATE_DIR="$STATE_ROOT/sess-123"

cat >"$FAKE_OZ" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_OZ_LOG:?}"

if [ "$#" -ge 3 ] && [ "$1" = "run" ] && [ "$2" = "message" ] && [ "$3" = "watch" ]; then
    if [ -n "${FAKE_OZ_WATCH_FILE:-}" ] && [ -f "${FAKE_OZ_WATCH_FILE:-}" ]; then
        cat "$FAKE_OZ_WATCH_FILE"
    fi
    exit 0
fi

if [ "$#" -ge 4 ] && [ "$1" = "run" ] && [ "$2" = "message" ] && [ "$3" = "mark-delivered" ]; then
    exit 0
fi

if [ "$#" -ge 4 ] && [ "$1" = "run" ] && [ "$2" = "message" ] && [ "$3" = "delivered" ]; then
    exit 0
fi

exit 0
EOF
chmod +x "$FAKE_OZ"

export OZ_CLI="$FAKE_OZ"
export OZ_RUN_ID="child-run-123"
export OZ_PARENT_RUN_ID="parent-run-456"
export OZ_PARENT_STATE_ROOT="$STATE_ROOT"
export FAKE_OZ_LOG
export FAKE_OZ_WATCH_FILE="$FAKE_OZ_WATCH"

mkdir -p "$STATE_ROOT"
: >"$FAKE_OZ_LOG"

echo "=== on-session-start.sh ==="
rm -rf "$STATE_DIR"
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-session-start.sh")
assert_eq "session start emits no output" "" "$OUTPUT"
assert_eq "session start writes listener pid" "true" "$([ -f "$STATE_DIR/listener.pid" ] && echo true || echo false)"
assert_eq "session start creates state directory" "true" "$([ -d "$STATE_DIR/staged" ] && echo true || echo false)"
kill_listener_pid="$(cat "$STATE_DIR/listener.pid" 2>/dev/null || true)"
if [ -n "$kill_listener_pid" ]; then
    kill "$kill_listener_pid" 2>/dev/null || true
fi
rm -rf "$STATE_DIR"

echo ""
echo "=== oz-parent-listener.sh ==="
cat >"$FAKE_OZ_WATCH" <<'EOF'
{"sequence":42,"message_id":"msg-123","sender_run_id":"parent-run-456","subject":"Please pivot","body":"Inspect the failing tests before editing code.","occurred_at":"2026-04-17T15:46:00Z"}
EOF

bash "$SCRIPT_DIR/oz-parent-listener.sh" "$STATE_DIR"

LISTENER_FILE="$STATE_DIR/staged/00000000000000000042-msg-123.json"
assert_eq "listener stages message" "true" "$([ -f "$LISTENER_FILE" ] && echo true || echo false)"
assert_json_field "listener writes stored subject" "$(cat "$LISTENER_FILE")" ".subject" "Please pivot"
assert_eq "listener updates last sequence" "42" "$(cat "$STATE_DIR/last-sequence")"
assert_contains "listener invokes message watch" "$(cat "$FAKE_OZ_LOG")" "run message watch child-run-123 --since-sequence 0 --output-format ndjson"

echo ""
echo "=== drain-mailbox.sh ==="
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/drain-mailbox.sh" UserPromptSubmit)
assert_json_field "drain outputs hook event name" "$OUTPUT" ".hookSpecificOutput.hookEventName" "UserPromptSubmit"
assert_contains "drain includes subject" "$OUTPUT" "Please pivot"
assert_contains "drain includes body" "$OUTPUT" "Inspect the failing tests before editing code."
assert_eq "drain removes surfaced message" "false" "$([ -f "$LISTENER_FILE" ] && echo true || echo false)"
assert_contains "drain marks message delivered" "$(cat "$FAKE_OZ_LOG")" "run message mark-delivered msg-123"

echo ""
echo "=== on-stop.sh ==="
mkdir -p "$STATE_DIR/staged"
cat >"$STATE_DIR/staged/00000000000000000043-msg-456.json" <<'EOF'
{"sequence":43,"message_id":"msg-456","sender_run_id":"parent-run-456","subject":"Another update","body":"There is still more work to do.","occurred_at":"2026-04-17T15:47:00Z"}
EOF

OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-stop.sh")
assert_json_field "stop blocks when staged messages remain" "$OUTPUT" ".decision" "block"
assert_contains "stop reason references pending parent messages" "$OUTPUT" "pending parent message"

rm -f "$STATE_DIR/staged/"*.json
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-stop.sh")
assert_eq "stop exits silently when no staged messages remain" "" "$OUTPUT"

echo ""
echo "=== on-session-end.sh ==="
printf '999999\n' >"$STATE_DIR/listener.pid"
mkdir -p "$STATE_DIR/staged"
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-session-end.sh")
assert_eq "session end emits no output" "" "$OUTPUT"
assert_eq "session end removes state directory" "false" "$([ -d "$STATE_DIR" ] && echo true || echo false)"

echo ""
echo "=== non-child sessions are ignored ==="
rm -rf "$STATE_DIR"
unset OZ_PARENT_RUN_ID
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-session-start.sh")
assert_eq "non-child session start emits no output" "" "$OUTPUT"
assert_eq "non-child session start does not create state directory" "false" "$([ -d "$STATE_DIR" ] && echo true || echo false)"
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/drain-mailbox.sh" UserPromptSubmit)
assert_eq "non-child drain emits no output" "" "$OUTPUT"
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-stop.sh")
assert_eq "non-child stop emits no output" "" "$OUTPUT"
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-session-end.sh")
assert_eq "non-child session end emits no output" "" "$OUTPUT"
export OZ_PARENT_RUN_ID="parent-run-456"

echo ""
echo "=== externally managed lifecycle and drain ==="
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR/staged" "$STATE_DIR/surfaced"
export OZ_PARENT_LISTENER_MANAGED_EXTERNALLY=1
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-session-start.sh")
assert_eq "externally managed session start emits no output" "" "$OUTPUT"
assert_eq "externally managed session start does not create pid file" "false" "$([ -f "$STATE_DIR/listener.pid" ] && echo true || echo false)"

cat >"$STATE_DIR/pending-hook-output.json" <<'EOF'
{"additional_context":"Lead-agent updates arrived from Oz. Treat the latest parent instructions below as authoritative.\n\n---\nParent message #44 from parent-run-456\nSubject: Driver-owned update\n\nSwitch to the new debugging plan.","remaining_staged_count":0,"surfaced_count":1}
EOF
cat >"$STATE_DIR/surfaced/00000000000000000044-msg-789.json" <<'EOF'
{"sequence":44,"message_id":"msg-789","sender_run_id":"parent-run-456","subject":"Driver-owned update","body":"Switch to the new debugging plan.","occurred_at":"2026-04-17T15:48:00Z"}
EOF

OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/drain-mailbox.sh" PostToolUse)
assert_json_field "externally managed drain outputs hook event name" "$OUTPUT" ".hookSpecificOutput.hookEventName" "PostToolUse"
assert_contains "externally managed drain includes driver-rendered context" "$OUTPUT" "Driver-owned update"
assert_eq "externally managed drain writes ack file" "true" "$([ -f "$STATE_DIR/pending-hook-output.ack" ] && echo true || echo false)"

OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-stop.sh")
assert_eq "externally managed stop ignores already-acked surfaced messages" "" "$OUTPUT"

rm -f "$STATE_DIR/pending-hook-output.ack"
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-stop.sh")
assert_json_field "externally managed stop blocks when surfaced messages are unacked" "$OUTPUT" ".decision" "block"

: >"$STATE_DIR/pending-hook-output.ack"
cat >"$STATE_DIR/staged/00000000000000000045-msg-790.json" <<'EOF'
{"sequence":45,"message_id":"msg-790","sender_run_id":"parent-run-456","subject":"Queued update","body":"There is still another staged instruction.","occurred_at":"2026-04-17T15:49:00Z"}
EOF
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-stop.sh")
assert_json_field "externally managed stop still blocks for newly staged messages" "$OUTPUT" ".decision" "block"
rm -f "$STATE_DIR/pending-hook-output.json" "$STATE_DIR/pending-hook-output.ack"
rm -f "$STATE_DIR/staged/"*.json "$STATE_DIR/surfaced/"*.json

export OZ_PARENT_STOP_LINGER_ATTEMPTS=10
export OZ_PARENT_STOP_LINGER_POLL_SECONDS=0.05
(
    sleep 0.1
    cat >"$STATE_DIR/staged/00000000000000000046-msg-791.json" <<'EOF'
{"sequence":46,"message_id":"msg-791","sender_run_id":"parent-run-456","subject":"Late update","body":"This parent message arrived during the linger window.","occurred_at":"2026-04-17T15:50:00Z"}
EOF
) &
linger_writer_pid=$!
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-stop.sh")
wait "$linger_writer_pid"
assert_json_field "externally managed stop lingers for late-arriving staged messages" "$OUTPUT" ".decision" "block"
assert_contains "externally managed linger reason references pending parent messages" "$OUTPUT" "pending parent message"
unset OZ_PARENT_STOP_LINGER_ATTEMPTS
unset OZ_PARENT_STOP_LINGER_POLL_SECONDS

rm -rf "$STATE_DIR"
OUTPUT=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/on-session-end.sh")
assert_eq "externally managed session end emits no output" "" "$OUTPUT"
assert_eq "externally managed session end does not recreate state directory" "false" "$([ -d "$STATE_DIR" ] && echo true || echo false)"
unset OZ_PARENT_LISTENER_MANAGED_EXTERNALLY

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
