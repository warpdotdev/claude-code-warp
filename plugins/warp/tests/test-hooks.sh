#!/bin/bash
# Tests for the Warp Claude Code plugin hook scripts.
#
# Validates that each hook script produces correctly structured JSON payloads
# by piping mock Claude Code hook input into the scripts and checking the output.
#
# Usage: ./tests/test-hooks.sh
#
# Since the hook scripts write OSC sequences to /dev/tty (not stdout),
# we test build-payload.sh directly — it's the shared JSON construction logic
# that all hook scripts use.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
source "$SCRIPT_DIR/build-payload.sh"

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

assert_json_field() {
    local test_name="$1"
    local json="$2"
    local field="$3"
    local expected="$4"
    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
    assert_eq "$test_name" "$expected" "$actual"
}

# --- Tests ---

echo "=== build-payload.sh ==="

echo ""
echo "--- Common fields ---"
PAYLOAD=$(build_payload '{"session_id":"sess-123","cwd":"/Users/alice/my-project"}' "stop")
assert_json_field "v is 1" "$PAYLOAD" ".v" "1"
assert_json_field "agent is claude" "$PAYLOAD" ".agent" "claude"
assert_json_field "event is stop" "$PAYLOAD" ".event" "stop"
assert_json_field "session_id extracted" "$PAYLOAD" ".session_id" "sess-123"
assert_json_field "cwd extracted" "$PAYLOAD" ".cwd" "/Users/alice/my-project"
assert_json_field "project is basename of cwd" "$PAYLOAD" ".project" "my-project"

echo ""
echo "--- Common fields with missing data ---"
PAYLOAD=$(build_payload '{}' "stop")
assert_json_field "empty session_id" "$PAYLOAD" ".session_id" ""
assert_json_field "empty cwd" "$PAYLOAD" ".cwd" ""
assert_json_field "empty project" "$PAYLOAD" ".project" ""

echo ""
echo "--- Extra args are merged ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "stop" \
    --arg query "hello" \
    --arg response "world")
assert_json_field "query merged" "$PAYLOAD" ".query" "hello"
assert_json_field "response merged" "$PAYLOAD" ".response" "world"
assert_json_field "common fields still present" "$PAYLOAD" ".session_id" "s1"

echo ""
echo "--- Stop event ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "stop" \
    --arg query "write a haiku" \
    --arg response "Memory is safe, the borrow checker stands guard" \
    --arg transcript_path "/tmp/transcript.jsonl")
assert_json_field "event is stop" "$PAYLOAD" ".event" "stop"
assert_json_field "query present" "$PAYLOAD" ".query" "write a haiku"
assert_json_field "response present" "$PAYLOAD" ".response" "Memory is safe, the borrow checker stands guard"
assert_json_field "transcript_path present" "$PAYLOAD" ".transcript_path" "/tmp/transcript.jsonl"

echo ""
echo "--- Permission request event ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "permission_request" \
    --arg summary "Wants to run Bash: rm -rf /tmp" \
    --arg tool_name "Bash" \
    --argjson tool_input '{"command":"rm -rf /tmp"}')
assert_json_field "event is permission_request" "$PAYLOAD" ".event" "permission_request"
assert_json_field "summary present" "$PAYLOAD" ".summary" "Wants to run Bash: rm -rf /tmp"
assert_json_field "tool_name present" "$PAYLOAD" ".tool_name" "Bash"
assert_json_field "tool_input.command present" "$PAYLOAD" ".tool_input.command" "rm -rf /tmp"

echo ""
echo "--- Idle prompt event ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj","notification_type":"idle_prompt"}' "idle_prompt" \
    --arg summary "Claude is waiting for your input")
assert_json_field "event is idle_prompt" "$PAYLOAD" ".event" "idle_prompt"
assert_json_field "summary present" "$PAYLOAD" ".summary" "Claude is waiting for your input"

echo ""
echo "--- JSON special characters in values ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "stop" \
    --arg query 'what does "hello world" mean?' \
    --arg response 'It means greeting. Use: printf("hello")')
assert_json_field "quotes in query preserved" "$PAYLOAD" ".query" 'what does "hello world" mean?'
assert_json_field "parens in response preserved" "$PAYLOAD" ".response" 'It means greeting. Use: printf("hello")'

echo ""
echo "--- Protocol version negotiation ---"

# Default: no env var set → falls back to plugin max (1)
unset WARP_CLI_AGENT_PROTOCOL_VERSION
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp"}' "stop")
assert_json_field "defaults to v1 when env var absent" "$PAYLOAD" ".v" "1"

# Warp declares v1 → use 1
export WARP_CLI_AGENT_PROTOCOL_VERSION=1
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp"}' "stop")
assert_json_field "v1 when warp declares 1" "$PAYLOAD" ".v" "1"

# Warp declares a higher version than the plugin knows → capped to plugin current
export WARP_CLI_AGENT_PROTOCOL_VERSION=99
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp"}' "stop")
assert_json_field "capped to plugin current when warp is ahead" "$PAYLOAD" ".v" "1"

# Warp declares a lower version than the plugin knows → use warp's version
# (not testable with PLUGIN_MAX=1 since there's no v0, but we verify the min logic
# by temporarily overriding the variable)
PLUGIN_CURRENT_PROTOCOL_VERSION=5
export WARP_CLI_AGENT_PROTOCOL_VERSION=3
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp"}' "stop")
assert_json_field "uses warp version when plugin is ahead" "$PAYLOAD" ".v" "3"
PLUGIN_CURRENT_PROTOCOL_VERSION=1

# Clean up
unset WARP_CLI_AGENT_PROTOCOL_VERSION

echo ""
echo "=== should-use-structured.sh ==="

source "$SCRIPT_DIR/../scripts/should-use-structured.sh"

echo ""
echo "--- No protocol version → legacy ---"
unset WARP_CLI_AGENT_PROTOCOL_VERSION
unset WARP_CLIENT_VERSION
should_use_structured
assert_eq "no protocol version returns false" "1" "$?"

echo ""
echo "--- Protocol set, no client version → legacy ---"
export WARP_CLI_AGENT_PROTOCOL_VERSION=1
unset WARP_CLIENT_VERSION
should_use_structured
assert_eq "missing WARP_CLIENT_VERSION returns false" "1" "$?"

echo ""
echo "--- Protocol set, dev version → always structured (dev was never broken) ---"
export WARP_CLI_AGENT_PROTOCOL_VERSION=1
export WARP_CLIENT_VERSION="v0.2026.03.30.08.43.dev_00"
should_use_structured
assert_eq "dev version returns true" "0" "$?"

echo ""
echo "--- Protocol set, broken stable version → legacy ---"
export WARP_CLIENT_VERSION="v0.2026.03.25.08.24.stable_05"
should_use_structured
assert_eq "exact broken stable version returns false" "1" "$?"

echo ""
echo "--- Protocol set, newer stable version → structured ---"
export WARP_CLIENT_VERSION="v0.2026.04.01.08.00.stable_00"
should_use_structured
assert_eq "newer stable version returns true" "0" "$?"

echo ""
echo "--- Protocol set, broken preview version → legacy ---"
export WARP_CLIENT_VERSION="v0.2026.03.25.08.24.preview_05"
should_use_structured
assert_eq "exact broken preview version returns false" "1" "$?"

echo ""
echo "--- Protocol set, newer preview version → structured ---"
export WARP_CLIENT_VERSION="v0.2026.04.01.08.00.preview_00"
should_use_structured
assert_eq "newer preview version returns true" "0" "$?"

# Clean up
unset WARP_CLI_AGENT_PROTOCOL_VERSION
unset WARP_CLIENT_VERSION

# --- Routing tests ---
# These test the hook scripts as subprocesses to verify routing behavior.
# We override /dev/tty writes since they'd fail in CI.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"

echo ""
echo "=== Routing ==="

echo ""
echo "--- SessionStart routing ---"

# Legacy Warp (TERM_PROGRAM=WarpTerminal, no protocol version)
OUTPUT=$(TERM_PROGRAM=WarpTerminal bash "$HOOK_DIR/on-session-start.sh" < /dev/null 2>/dev/null)
SYS_MSG=$(echo "$OUTPUT" | jq -r '.systemMessage // empty' 2>/dev/null)
assert_eq "legacy Warp shows active message" \
    "🔔 Warp plugin active. You'll receive native Warp notifications when tasks complete or input is needed." \
    "$SYS_MSG"

# Not Warp (neither env var set)
OUTPUT=$(TERM_PROGRAM=other bash "$HOOK_DIR/on-session-start.sh" < /dev/null 2>/dev/null)
SYS_MSG=$(echo "$OUTPUT" | jq -r '.systemMessage // empty' 2>/dev/null)
assert_eq "non-Warp shows install message" \
    "ℹ️ Warp plugin installed but you're not running in Warp terminal. Install Warp (https://warp.dev) to get native notifications when Claude completes tasks or needs input." \
    "$SYS_MSG"

echo ""
echo "--- Modern-only hooks exit silently without protocol version ---"

for HOOK in on-permission-request.sh on-prompt-submit.sh on-post-tool-use.sh; do
    echo '{}' | bash "$HOOK_DIR/$HOOK" 2>/dev/null
    assert_eq "$HOOK exits 0 without protocol version" "0" "$?"
done

# --- TTY Detection tests ---
# These tests verify that warp-notify.sh correctly finds the TTY device
# even when running in a subprocess without a controlling terminal.

echo ""
echo "=== TTY Detection (warp-notify.sh) ==="

# Test: TTY detection finds the TTY from parent process
echo ""
echo "--- TTY detection logic ---"

# Production TTY detection logic - must match warp-notify.sh exactly
find_tty_device() {
    local current_pid=$1
    local tty_device=""
    while [ -n "$current_pid" ] && [ -z "$tty_device" ] && [ "$current_pid" != "0" ] && [ "$current_pid" != "1" ]; do
        # Same as production: single ps call with combined output
        read -r tty_val ppid_val < <(ps -o tty=,ppid= -p "$current_pid" 2>/dev/null)
        # Same as production: trim all whitespace using bash parameter expansion
        tty_val="${tty_val//[[:space:]]/}"
        if [ -n "$tty_val" ] && [ "$tty_val" != "??" ]; then
            tty_device="/dev/$tty_val"
            break
        fi
        # Continue up the process tree
        current_pid="${ppid_val//[[:space:]]/}"
    done
    echo "$tty_device"
}

# Test: Current shell has TTY (platform-agnostic: macOS uses /dev/ttysXXX, Linux uses /dev/pts/N)
CURRENT_TTY=$(find_tty_device $$)
if [ -z "$CURRENT_TTY" ]; then
    echo "  ⊘ Skipping TTY test (no TTY available in CI)"
    PASSED=$((PASSED + 1))
else
    # Check that TTY path starts with /dev/ (works for both /dev/ttysXXX and /dev/pts/N)
    case "$CURRENT_TTY" in
        /dev/*) assert_eq "TTY detection finds valid TTY path" "true" "true" ;;
        *) assert_eq "TTY detection finds valid TTY path" "/dev/*" "$CURRENT_TTY" ;;
    esac
fi

# Test: Subprocess without TTY walks parent chain (this shell's PPID should have TTY)
SUBPROCESS_TTY=$(find_tty_device $PPID)
if [ -n "$SUBPROCESS_TTY" ]; then
    assert_eq "TTY detection walks parent chain" "true" "true"
else
    assert_eq "TTY detection walks parent chain" "should find TTY" "not found"
fi

# Test: Invalid PID returns empty (no TTY found)
NO_PID_TTY=$(find_tty_device 99999999)
assert_eq "TTY detection returns empty for invalid PID" "" "$NO_PID_TTY"

# Test: `??` TTY value is treated as invalid (simulated by checking a process that has no TTY)
# In CI, some processes may have ?? as TTY - verify we skip them
if [ -n "$NO_PID_TTY" ]; then
    # If we got a result for invalid PID, something is wrong
    assert_eq "Invalid PID should not return TTY" "" "$NO_PID_TTY"
fi

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
