#!/bin/bash
# Warp notification on Cline pre-tool-use (permission request)

command -v jq &>/dev/null || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/warp-notify.sh"
should_use_structured || exit 0

read_hook_input
TOOL_NAME=$(echo "$INPUT" | jq -r '.preToolUse.toolName // .tool_call.name // "unknown"' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_call.input // .preToolUse.parameters // {}' 2>/dev/null)
[ -z "$TOOL_INPUT" ] && TOOL_INPUT='{}'

SUMMARY="Wants to run $TOOL_NAME"

BODY=$(jq -nc \
    --argjson v 1 \
    --arg agent "cline" \
    --arg event "permission_request" \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg project "$PROJECT" \
    --arg summary "$SUMMARY" \
    --arg tool_name "$TOOL_NAME" \
    --argjson tool_input "$TOOL_INPUT" \
    '{v:$v, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project, summary:$summary, tool_name:$tool_name, tool_input:$tool_input}')

warp_notify "$BODY"
