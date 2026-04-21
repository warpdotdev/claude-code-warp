#!/bin/bash
# Hook script for Claude Code SubagentStart event
# Emits subagent_start so the sidebar can visualize nested agent runs instead
# of showing a flat "running" state for the whole parent turn.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#subagentstart-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"' 2>/dev/null)

BODY=$(build_payload "$INPUT" "subagent_start" \
    --arg agent_id "$AGENT_ID" \
    --arg agent_type "$AGENT_TYPE")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
