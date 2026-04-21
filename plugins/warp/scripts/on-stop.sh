#!/bin/bash
# Hook script for Claude Code Stop event
# Sends a structured Warp notification when Claude completes a turn.
#
# Claude Code's Stop hook input now exposes `last_assistant_message` directly,
# so the previous 0.3s sleep + JSONL transcript parse is obsolete. The user's
# prompt is read from a session-scoped temp file written by on-prompt-submit.sh.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#stop-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Legacy fallback for old Warp versions
if ! should_use_structured; then
    [ "$TERM_PROGRAM" = "WarpTerminal" ] && exec "$SCRIPT_DIR/legacy/on-stop.sh"
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

# stop_hook_active is true when this hook is re-running because a prior Stop
# hook returned decision:"block". Skip to avoid double-notifications.
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Claude's final response — directly available in the hook input.
RESPONSE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)
if [ -n "$RESPONSE" ] && [ ${#RESPONSE} -gt 200 ]; then
    RESPONSE="${RESPONSE:0:197}..."
fi

# User's last prompt — written by on-prompt-submit.sh to a session-scoped temp file.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
QUERY_FILE="${TMPDIR:-/tmp}/warp-claude-${SESSION_ID}.query"
QUERY=""
if [ -n "$SESSION_ID" ] && [ -f "$QUERY_FILE" ]; then
    QUERY=$(cat "$QUERY_FILE" 2>/dev/null)
    if [ -n "$QUERY" ] && [ ${#QUERY} -gt 200 ]; then
        QUERY="${QUERY:0:197}..."
    fi
fi

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
PERMISSION_MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)

BODY=$(build_payload "$INPUT" "stop" \
    --arg query "$QUERY" \
    --arg response "$RESPONSE" \
    --arg transcript_path "$TRANSCRIPT_PATH" \
    --arg permission_mode "$PERMISSION_MODE")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
