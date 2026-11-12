#!/bin/bash
# Warp notification on Cline task complete

command -v jq &>/dev/null || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/warp-notify.sh"
should_use_structured || exit 0

read_hook_input
RESPONSE=$(truncate_text "$(echo "$INPUT" | jq -r '.turn.outputText // empty' 2>/dev/null)")

BODY=$(jq -nc \
    --argjson v 1 \
    --arg agent "cline" \
    --arg event "stop" \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg project "$PROJECT" \
    --arg query "" \
    --arg response "$RESPONSE" \
    '{v:$v, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project, query:$query, response:$response}')

warp_notify "$BODY"
