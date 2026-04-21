#!/bin/bash
# Hook script for Claude Code PostToolUse event
# Sends a structured Warp notification after a tool call completes, transitioning
# the session from "blocked-on-tool" → "running".
#
# The matcher in hooks.json narrows this to state-transition tools (Bash, Edit,
# Write, MultiEdit, Agent, NotebookEdit). Cheap read-only tools (Read, Glob,
# Grep, WebFetch) would spawn this hook 50–100 times per session and generate
# sidebar noise without meaningful state change.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#posttooluse-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Compact preview of what the tool actually did — lets the sidebar show
# "Edit: src/foo.ts" instead of just "Edit".
TOOL_PREVIEW=$(echo "$INPUT" | jq -r '(.tool_input | if .command then .command elif .file_path then .file_path elif .url then .url elif .description then .description else "" end) // ""' 2>/dev/null)
if [ -n "$TOOL_PREVIEW" ] && [ ${#TOOL_PREVIEW} -gt 120 ]; then
    TOOL_PREVIEW="${TOOL_PREVIEW:0:117}..."
fi

PERMISSION_MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)

BODY=$(build_payload "$INPUT" "tool_complete" \
    --arg tool_name "$TOOL_NAME" \
    --arg tool_preview "$TOOL_PREVIEW" \
    --arg permission_mode "$PERMISSION_MODE")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
