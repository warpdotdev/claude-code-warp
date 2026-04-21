#!/bin/bash
# Hook script for Claude Code StopFailure event
# Fires instead of Stop when the turn ends because of an API error (rate limit,
# auth, billing, server). Without this hook, Warp's sidebar would stay in
# "running" state forever since `stop` never fires on errors.
#
# Uses the existing `stop` event with an added `error` field so older Warp
# builds still transition the tab to done; new builds can render it as failed.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#stopfailure-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

# error: "rate_limit", "authentication_failed", "billing_error",
#        "invalid_request", "server_error", "max_output_tokens", "unknown"
ERROR=$(echo "$INPUT" | jq -r '.error // "unknown"' 2>/dev/null)
ERROR_DETAILS=$(echo "$INPUT" | jq -r '.error_details // empty' 2>/dev/null)
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)

# Recover the last user prompt from the session-scoped temp file written by
# on-prompt-submit.sh. Provides context for "what was the user doing when this failed".
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
QUERY_FILE="${TMPDIR:-/tmp}/warp-claude-${SESSION_ID}.query"
QUERY=""
if [ -n "$SESSION_ID" ] && [ -f "$QUERY_FILE" ]; then
    QUERY=$(cat "$QUERY_FILE" 2>/dev/null)
    if [ -n "$QUERY" ] && [ ${#QUERY} -gt 200 ]; then
        QUERY="${QUERY:0:197}..."
    fi
fi

# Compose a human-readable error line. `last_assistant_message` for StopFailure
# holds the rendered error text, not Claude's output — use it directly.
if [ -n "$LAST_MSG" ]; then
    RESPONSE="$LAST_MSG"
else
    RESPONSE="Error: $ERROR"
    [ -n "$ERROR_DETAILS" ] && RESPONSE="$RESPONSE — $ERROR_DETAILS"
fi
if [ ${#RESPONSE} -gt 200 ]; then
    RESPONSE="${RESPONSE:0:197}..."
fi

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

BODY=$(build_payload "$INPUT" "stop" \
    --arg query "$QUERY" \
    --arg response "$RESPONSE" \
    --arg error "$ERROR" \
    --arg error_details "$ERROR_DETAILS" \
    --arg transcript_path "$TRANSCRIPT_PATH")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
