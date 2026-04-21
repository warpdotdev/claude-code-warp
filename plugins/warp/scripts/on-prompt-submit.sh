#!/bin/bash
# Hook script for Claude Code UserPromptSubmit event
# Sends a structured Warp notification when the user submits a prompt,
# transitioning the session from idle/done → running.
#
# Also persists the full prompt to a session-scoped temp file so the Stop hook
# can reference it in the completion summary without re-parsing the transcript.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#userpromptsubmit-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

FULL_QUERY=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
QUERY="$FULL_QUERY"
if [ -n "$QUERY" ] && [ ${#QUERY} -gt 200 ]; then
    QUERY="${QUERY:0:197}..."
fi

# Persist the full prompt so the Stop hook can reconstruct "query → response".
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$SESSION_ID" ] && [ -n "$FULL_QUERY" ]; then
    QUERY_FILE="${TMPDIR:-/tmp}/warp-claude-${SESSION_ID}.query"
    printf '%s' "$FULL_QUERY" > "$QUERY_FILE" 2>/dev/null || true
fi

PERMISSION_MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)

BODY=$(build_payload "$INPUT" "prompt_submit" \
    --arg query "$QUERY" \
    --arg permission_mode "$PERMISSION_MODE")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
