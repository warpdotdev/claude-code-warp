#!/bin/bash
# Warp notification on Cline post-tool-use

[ -z "${WARP_CLI_AGENT_PROTOCOL_VERSION:-}" ] && exit 0
[ -z "${WARP_CLIENT_VERSION:-}" ] && exit 0

command -v jq &>/dev/null || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$INPUT" | jq -r '.conversationId // .session_id // "unknown"' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$(pwd)"
PROJECT=$(basename "$CWD")

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool // .tool_name // empty' 2>/dev/null)

BODY=$(jq -nc \
    --argjson v 1 \
    --arg agent "cline" \
    --arg event "tool_complete" \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg project "$PROJECT" \
    --arg tool_name "$TOOL_NAME" \
    '{v:$v, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project, tool_name:$tool_name}')

printf '\033]777;notify;%s;%s\007' "warp://cli-agent" "$BODY" > /dev/tty 2>/dev/null || true
