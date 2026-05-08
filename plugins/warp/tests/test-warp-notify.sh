#!/bin/bash
# Tests for warp-notify.sh hang protection.
#
# Verifies that warp-notify.sh:
#   1. Completes immediately when the target is writable (the happy path).
#   2. Exits cleanly within the configured timeout when the target's output
#      buffer is full and never drained (the bug scenario: Warp UI hung).
#   3. Defaults to a sane upper bound (2s) without explicit configuration.
#   4. Same guarantees apply to the legacy variant.
#
# Implementation notes:
#   - We simulate "Warp UI hung" by pointing WARP_NOTIFY_TARGET at a FIFO
#     with no reader. The kernel blocks open()/write() on such a FIFO the
#     same way it blocks writes to a slave PTY whose master isn't reading,
#     which is the exact failure mode we observed in production.
#   - We export WARP_CLI_AGENT_PROTOCOL_VERSION and WARP_CLIENT_VERSION so
#     should_use_structured returns true and we exercise the write path.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"

export WARP_CLI_AGENT_PROTOCOL_VERSION=1
export WARP_CLIENT_VERSION="v0.2026.04.01.08.00.stable_00"

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

assert_lt() {
    local test_name="$1"
    local actual="$2"
    local upper="$3"
    if [ "$actual" -lt "$upper" ] 2>/dev/null; then
        echo "  ✓ $test_name ($actual < $upper)"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ $test_name (got $actual, expected < $upper)"
        FAILED=$((FAILED + 1))
    fi
}

cleanup() {
    [ -n "${FIFO:-}" ] && rm -f "$FIFO"
}
trap cleanup EXIT

run_notify() {
    local script="$1"
    shift
    local start end
    start=$(date +%s)
    bash "$script" "warp://cli-agent" '{"v":1,"agent":"claude","event":"test"}' "$@"
    LAST_RC=$?
    end=$(date +%s)
    LAST_ELAPSED=$((end - start))
}

echo "=== warp-notify.sh hang protection ==="

echo ""
echo "--- Fast path: writable target completes immediately ---"
WARP_NOTIFY_TARGET=/dev/null run_notify "$SCRIPT_DIR/warp-notify.sh"
assert_eq "writable target exits 0" "0" "$LAST_RC"
assert_lt "writable target completes under 2s" "$LAST_ELAPSED" "2"

echo ""
echo "--- Hang protection: blocked target times out at configured limit ---"
FIFO=$(mktemp -u)
mkfifo "$FIFO"
WARP_NOTIFY_TARGET="$FIFO" WARP_NOTIFY_TIMEOUT_SEC=1 \
    run_notify "$SCRIPT_DIR/warp-notify.sh"
assert_eq "blocked target still exits 0 (best-effort)" "0" "$LAST_RC"
# Timeout=1s plus watchdog/teardown overhead — generous bound to avoid CI flake.
assert_lt "blocked target exits within 4s" "$LAST_ELAPSED" "4"
rm -f "$FIFO"

echo ""
echo "--- Default timeout caps unbounded waits ---"
FIFO=$(mktemp -u)
mkfifo "$FIFO"
WARP_NOTIFY_TARGET="$FIFO" run_notify "$SCRIPT_DIR/warp-notify.sh"
assert_eq "default timeout still exits 0" "0" "$LAST_RC"
# Default is 2s; allow 5s for CI scheduling jitter.
assert_lt "default timeout exits within 5s" "$LAST_ELAPSED" "5"
rm -f "$FIFO"

echo ""
echo "=== legacy/warp-notify.sh hang protection ==="

echo ""
echo "--- Fast path: writable target completes immediately ---"
WARP_NOTIFY_TARGET=/dev/null run_notify "$SCRIPT_DIR/legacy/warp-notify.sh"
assert_eq "legacy writable target exits 0" "0" "$LAST_RC"
assert_lt "legacy writable target completes under 2s" "$LAST_ELAPSED" "2"

echo ""
echo "--- Hang protection: blocked target times out ---"
FIFO=$(mktemp -u)
mkfifo "$FIFO"
WARP_NOTIFY_TARGET="$FIFO" WARP_NOTIFY_TIMEOUT_SEC=1 \
    run_notify "$SCRIPT_DIR/legacy/warp-notify.sh"
assert_eq "legacy blocked target still exits 0" "0" "$LAST_RC"
assert_lt "legacy blocked target exits within 4s" "$LAST_ELAPSED" "4"
rm -f "$FIFO"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
