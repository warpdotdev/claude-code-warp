#!/bin/bash
# Hook script for Claude Code PostToolUse event
# Sends a structured Warp notification after a tool call completes,
# transitioning the session status from Blocked back to Running.

# Fast-path: skip immediately in non-Warp environments (subagents, CI, other terminals)
[ -z "${WARP_CLI_AGENT_PROTOCOL_VERSION:-}" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Full version gate for broken Warp builds
if ! should_use_structured; then
    exit 0
fi

# Negotiate protocol version: min(plugin_current=1, warp_declared)
PROTOCOL_VERSION="${WARP_CLI_AGENT_PROTOCOL_VERSION:-1}"
[ "$PROTOCOL_VERSION" -gt 1 ] 2>/dev/null && PROTOCOL_VERSION=1

# Single jq call: read stdin, extract fields, build payload in one pass
BODY=$(jq -nc \
    --argjson v "$PROTOCOL_VERSION" \
    --arg agent "claude" \
    --arg event "tool_complete" \
    '{v:$v, agent:$agent, event:$event}
     + (input | {session_id: (.session_id // ""), cwd: (.cwd // ""), project: ((.cwd // "") | split("/") | last // ""), tool_name: (.tool_name // "")})')

# Non-blocking tty write: background to avoid stalling on PTY congestion
# during heavy terminal render (eliminates 2s+ spikes under load).
printf '\033]777;notify;%s;%s\007' "warp://cli-agent" "$BODY" > /dev/tty 2>/dev/null &
