#!/bin/bash
# Hook script for Claude Code PostToolUse event
# Sends a structured Warp notification after a tool call completes,
# transitioning the session status from Blocked back to Running.

[ -z "${WARP_CLI_AGENT_PROTOCOL_VERSION:-}" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

PROTOCOL_VERSION="${WARP_CLI_AGENT_PROTOCOL_VERSION:-1}"
[[ "$PROTOCOL_VERSION" =~ ^[0-9]+$ ]] || PROTOCOL_VERSION=1
[ "$PROTOCOL_VERSION" -gt 1 ] && PROTOCOL_VERSION=1

# Single jq invocation: reads hook stdin directly, builds entire payload
BODY=$(jq -nc \
    --argjson v "$PROTOCOL_VERSION" \
    --arg agent "claude" \
    --arg event "tool_complete" \
    '{v:$v, agent:$agent, event:$event}
     + (input | {session_id: (.session_id // ""), cwd: (.cwd // ""), project: ((.cwd // "") | sub(".*/"; "")), tool_name: (.tool_name // "")})')

printf '\033]777;notify;%s;%s\007' "warp://cli-agent" "$BODY" > /dev/tty 2>/dev/null &
