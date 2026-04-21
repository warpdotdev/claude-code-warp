#!/bin/bash
# Hook script for Claude Code SubagentStop event
# Emits subagent_stop with the nested agent's final response so the sidebar can
# show the outcome of each subagent, not just the parent Agent tool call.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#subagentstop-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

# Guard against double-notification on stop-hook re-entry.
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"' 2>/dev/null)
AGENT_TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.agent_transcript_path // empty' 2>/dev/null)
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)
if [ -n "$LAST_MSG" ] && [ ${#LAST_MSG} -gt 200 ]; then
    LAST_MSG="${LAST_MSG:0:197}..."
fi

BODY=$(build_payload "$INPUT" "subagent_stop" \
    --arg agent_id "$AGENT_ID" \
    --arg agent_type "$AGENT_TYPE" \
    --arg response "$LAST_MSG" \
    --arg transcript_path "$AGENT_TRANSCRIPT_PATH")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
