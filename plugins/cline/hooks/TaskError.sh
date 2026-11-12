#!/bin/bash
# Warp notification on Cline task error

command -v jq &>/dev/null || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/warp-notify.sh"
should_use_structured || exit 0

read_hook_input
ERROR=$(truncate_text "$(echo "$INPUT" | jq -r '.error.message // empty' 2>/dev/null)")
SUMMARY="Task errored"
[ -n "$ERROR" ] && SUMMARY="Task errored: $ERROR"

BODY=$(jq -nc \
    --argjson v 1 \
    --arg agent "cline" \
    --arg event "stop" \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg project "$PROJECT" \
    --arg summary "$SUMMARY" \
    '{v:$v, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project, summary:$summary}')

warp_notify "$BODY"
