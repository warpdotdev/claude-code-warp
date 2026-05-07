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

source "$SCRIPT_DIR/build-payload.sh"

# Read hook input from stdin
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

BODY=$(build_payload "$INPUT" "tool_complete" \
    --arg tool_name "$TOOL_NAME")

# Inline the OSC 777 write — avoids spawning warp-notify.sh subprocess
# which would re-source should-use-structured.sh and re-run the gate check.
printf '\033]777;notify;%s;%s\007' "warp://cli-agent" "$BODY" > /dev/tty 2>/dev/null || true
