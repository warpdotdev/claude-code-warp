#!/bin/bash
# Warp notification on Cline post-tool-use

command -v jq &>/dev/null || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/warp-notify.sh"
should_use_structured || exit 0

read_hook_input
TOOL_NAME=$(echo "$INPUT" | jq -r '.postToolUse.toolName // .tool_result.name // empty' 2>/dev/null)

BODY=$(jq -nc \
    --argjson v 1 \
    --arg agent "cline" \
    --arg event "tool_complete" \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg project "$PROJECT" \
    --arg tool_name "$TOOL_NAME" \
    '{v:$v, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project, tool_name:$tool_name}')

warp_notify "$BODY"
