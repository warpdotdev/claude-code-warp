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

echo ""
echo "--- Modern-only hooks exit silently without protocol version ---"

unset WARP_CLI_AGENT_PROTOCOL_VERSION
unset WARP_CLIENT_VERSION
for HOOK in \
    on-permission-request.sh \
    on-permission-denied.sh \
    on-prompt-submit.sh \
    on-post-tool-use.sh \
    on-post-tool-use-failure.sh \
    on-session-end.sh \
    on-stop-failure.sh \
    on-subagent-start.sh \
    on-subagent-stop.sh \
    on-pre-compact.sh \
    on-post-compact.sh \
    on-cwd-changed.sh \
    on-elicitation.sh; do
    echo '{}' | bash "$HOOK_DIR/$HOOK" 2>/dev/null
    assert_eq "$HOOK exits 0 without protocol version" "0" "$?"
done

# --- New event payload shapes ---
# Each new event is tested through build_payload (the shared JSON construction
# layer all hook scripts use) since hook scripts themselves write to /dev/tty.

echo ""
echo "=== new event payloads ==="

echo ""
echo "--- session_start enriches with source/model/permission_mode ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "session_start" \
    --arg plugin_version "3.0.0" \
    --arg source "resume" \
    --arg model "claude-sonnet-4-6" \
    --arg permission_mode "acceptEdits" \
    --arg agent_type "")
assert_json_field "session_start event name" "$PAYLOAD" ".event" "session_start"
assert_json_field "plugin_version present" "$PAYLOAD" ".plugin_version" "3.0.0"
assert_json_field "source present" "$PAYLOAD" ".source" "resume"
assert_json_field "model present" "$PAYLOAD" ".model" "claude-sonnet-4-6"
assert_json_field "permission_mode present" "$PAYLOAD" ".permission_mode" "acceptEdits"

echo ""
echo "--- session_end with reason ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "session_end" \
    --arg reason "clear")
assert_json_field "session_end event name" "$PAYLOAD" ".event" "session_end"
assert_json_field "reason present" "$PAYLOAD" ".reason" "clear"

echo ""
echo "--- stop with error (StopFailure mapping) ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "stop" \
    --arg query "refactor auth" \
    --arg response "API Error: Rate limit reached" \
    --arg error "rate_limit" \
    --arg error_details "429 Too Many Requests" \
    --arg transcript_path "")
assert_json_field "stop event name for failures" "$PAYLOAD" ".event" "stop"
assert_json_field "error field present" "$PAYLOAD" ".error" "rate_limit"
assert_json_field "error_details present" "$PAYLOAD" ".error_details" "429 Too Many Requests"
assert_json_field "response holds error text" "$PAYLOAD" ".response" "API Error: Rate limit reached"

echo ""
echo "--- permission_denied ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "permission_denied" \
    --arg summary "Auto-denied Bash: rm -rf /" \
    --arg tool_name "Bash" \
    --argjson tool_input '{"command":"rm -rf /"}' \
    --arg reason "command targets a path outside the project")
assert_json_field "permission_denied event name" "$PAYLOAD" ".event" "permission_denied"
assert_json_field "summary present" "$PAYLOAD" ".summary" "Auto-denied Bash: rm -rf /"
assert_json_field "reason present" "$PAYLOAD" ".reason" "command targets a path outside the project"
assert_json_field "tool_input preserved" "$PAYLOAD" ".tool_input.command" "rm -rf /"

echo ""
echo "--- tool_failed ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "tool_failed" \
    --arg tool_name "Bash" \
    --arg error "Command exited with non-zero status code 1" \
    --arg tool_preview "npm test" \
    --argjson is_interrupt false)
assert_json_field "tool_failed event name" "$PAYLOAD" ".event" "tool_failed"
assert_json_field "tool_name present" "$PAYLOAD" ".tool_name" "Bash"
assert_json_field "error present" "$PAYLOAD" ".error" "Command exited with non-zero status code 1"
assert_json_field "tool_preview present" "$PAYLOAD" ".tool_preview" "npm test"
assert_json_field "is_interrupt is bool" "$PAYLOAD" ".is_interrupt" "false"

echo ""
echo "--- subagent_start ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "subagent_start" \
    --arg agent_id "agent-abc123" \
    --arg agent_type "Explore")
assert_json_field "subagent_start event name" "$PAYLOAD" ".event" "subagent_start"
assert_json_field "agent_id present" "$PAYLOAD" ".agent_id" "agent-abc123"
assert_json_field "agent_type present" "$PAYLOAD" ".agent_type" "Explore"

echo ""
echo "--- subagent_stop with response ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "subagent_stop" \
    --arg agent_id "agent-abc123" \
    --arg agent_type "Explore" \
    --arg response "Found 3 potential issues" \
    --arg transcript_path "/tmp/subagent.jsonl")
assert_json_field "subagent_stop event name" "$PAYLOAD" ".event" "subagent_stop"
assert_json_field "response present" "$PAYLOAD" ".response" "Found 3 potential issues"
assert_json_field "agent_type present" "$PAYLOAD" ".agent_type" "Explore"

echo ""
echo "--- compact_start / compact_end ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "compact_start" \
    --arg trigger "auto")
assert_json_field "compact_start event name" "$PAYLOAD" ".event" "compact_start"
assert_json_field "trigger present" "$PAYLOAD" ".trigger" "auto"

PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "compact_end" \
    --arg trigger "manual")
assert_json_field "compact_end event name" "$PAYLOAD" ".event" "compact_end"

echo ""
echo "--- cwd_changed uses envelope cwd ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/new/project/path"}' "cwd_changed")
assert_json_field "cwd_changed event name" "$PAYLOAD" ".event" "cwd_changed"
assert_json_field "cwd reflects new dir" "$PAYLOAD" ".cwd" "/new/project/path"
assert_json_field "project is new basename" "$PAYLOAD" ".project" "path"

echo ""
echo "--- question_asked (MCP elicitation) ---"
PAYLOAD=$(build_payload '{"session_id":"s1","cwd":"/tmp/proj"}' "question_asked" \
    --arg tool_name "github-server" \
    --arg summary "Which repo should I search?")
assert_json_field "question_asked event name" "$PAYLOAD" ".event" "question_asked"
assert_json_field "tool_name holds server name" "$PAYLOAD" ".tool_name" "github-server"
assert_json_field "summary present" "$PAYLOAD" ".summary" "Which repo should I search?"

# --- Temp-file prompt persistence ---
# The on-prompt-submit → on-stop handoff goes through a session-scoped temp file.
# Verify the file is created and consumed correctly.

echo ""
echo "=== temp-file prompt persistence ==="

export WARP_CLI_AGENT_PROTOCOL_VERSION=1
export WARP_CLIENT_VERSION="v0.2099.12.31.23.59.stable_99"

TEST_SESSION="test-session-$$"
TEST_TMP="${TMPDIR:-/tmp}/warp-claude-${TEST_SESSION}.query"
rm -f "$TEST_TMP"

# on-prompt-submit should write the full prompt to the temp file
INPUT=$(jq -nc --arg sid "$TEST_SESSION" '{session_id:$sid,cwd:"/tmp/proj",prompt:"refactor the auth module"}')
echo "$INPUT" | bash "$HOOK_DIR/on-prompt-submit.sh" 2>/dev/null >/dev/null

if [ -f "$TEST_TMP" ]; then
    CONTENT=$(cat "$TEST_TMP")
    assert_eq "on-prompt-submit writes query file" "refactor the auth module" "$CONTENT"
else
    assert_eq "on-prompt-submit writes query file" "refactor the auth module" "<no file created>"
fi

# on-session-end should clean up the temp file
INPUT=$(jq -nc --arg sid "$TEST_SESSION" '{session_id:$sid,cwd:"/tmp/proj",reason:"clear"}')
echo "$INPUT" | bash "$HOOK_DIR/on-session-end.sh" 2>/dev/null >/dev/null

if [ ! -f "$TEST_TMP" ]; then
    assert_eq "on-session-end cleans up query file" "cleaned" "cleaned"
else
    assert_eq "on-session-end cleans up query file" "cleaned" "still present"
    rm -f "$TEST_TMP"
fi

unset WARP_CLI_AGENT_PROTOCOL_VERSION
unset WARP_CLIENT_VERSION

# --- Summary ---

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
