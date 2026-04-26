#!/bin/bash
# Warp notification on Cline user prompt submit

[ -z "${WARP_CLI_AGENT_PROTOCOL_VERSION:-}" ] && exit 0
[ -z "${WARP_CLIENT_VERSION:-}" ] && exit 0

command -v jq &>/dev/null || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$INPUT" | jq -r '.conversationId // .session_id // "unknown"' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$(pwd)"
PROJECT=$(basename "$CWD")

QUERY=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -n "$QUERY" ] && [ ${#QUERY} -gt 200 ] && QUERY="${QUERY:0:197}..."

BODY=$(jq -nc \
    --argjson v 1 \
    --arg agent "cline" \
    --arg event "prompt_submit" \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg project "$PROJECT" \
    --arg query "$QUERY" \
    '{v:$v, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project, query:$query}')

printf '\033]777;notify;%s;%s\007' "warp://cli-agent" "$BODY" > /dev/tty 2>/dev/null || true
