#!/bin/bash
# Hook script for Claude Code PostToolUseFailure event
# Emits tool_failed so the sidebar can distinguish failed tool calls (red) from
# successful ones (green). Without this hook, a tool failure looks identical to
# a success in the sidebar — both just transition state.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#posttoolusefailure-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
ERROR=$(echo "$INPUT" | jq -r '.error // empty' 2>/dev/null)
IS_INTERRUPT=$(echo "$INPUT" | jq -r '.is_interrupt // false' 2>/dev/null)

if [ -n "$ERROR" ] && [ ${#ERROR} -gt 200 ]; then
    ERROR="${ERROR:0:197}..."
fi

# Short preview of the failed invocation for the sidebar.
TOOL_PREVIEW=$(echo "$INPUT" | jq -r '(.tool_input | if .command then .command elif .file_path then .file_path elif .url then .url elif .description then .description else "" end) // ""' 2>/dev/null)
if [ -n "$TOOL_PREVIEW" ] && [ ${#TOOL_PREVIEW} -gt 120 ]; then
    TOOL_PREVIEW="${TOOL_PREVIEW:0:117}..."
fi

BODY=$(build_payload "$INPUT" "tool_failed" \
    --arg tool_name "$TOOL_NAME" \
    --arg error "$ERROR" \
    --arg tool_preview "$TOOL_PREVIEW" \
    --argjson is_interrupt "$IS_INTERRUPT")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
