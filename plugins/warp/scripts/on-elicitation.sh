#!/bin/bash
# Hook script for Claude Code Elicitation event
# MCP servers can request user input mid-tool-execution via elicitation.
# This maps directly to OpenCode's `question_asked` event — Warp already has
# UI wired for it, so re-using that event gets MCP elicitation into the
# sidebar with zero new event registration on Warp's side.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#elicitation-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

# Elicitation's matcher is the MCP server name; it also appears in tool_name.
SERVER_NAME=$(echo "$INPUT" | jq -r '.server_name // .tool_name // "unknown"' 2>/dev/null)
MESSAGE=$(echo "$INPUT" | jq -r '.message // .requestedSchema.description // empty' 2>/dev/null)

if [ -n "$MESSAGE" ] && [ ${#MESSAGE} -gt 200 ]; then
    MESSAGE="${MESSAGE:0:197}..."
fi

BODY=$(build_payload "$INPUT" "question_asked" \
    --arg tool_name "$SERVER_NAME" \
    --arg summary "$MESSAGE")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
