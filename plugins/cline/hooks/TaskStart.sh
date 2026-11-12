#!/bin/bash
# Warp notification on Cline task start

command -v jq &>/dev/null || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/warp-notify.sh"
should_use_structured || exit 0

read_hook_input

BODY=$(jq -nc \
    --argjson v 1 \
    --arg agent "cline" \
    --arg event "session_start" \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg project "$PROJECT" \
    '{v:$v, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project}')

warp_notify "$BODY"
