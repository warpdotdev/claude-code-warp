#!/bin/bash
# Warp notification utility using OSC escape sequences
# Usage: warp-notify.sh <title> <body>
#
# For structured Warp notifications, title should be "warp://cli-agent"
# and body should be a JSON string matching the cli-agent notification schema.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Only emit notifications when we've confirmed the Warp build can render them.
if ! should_use_structured; then
    exit 0
fi

TITLE="${1:-Notification}"
BODY="${2:-}"

# OSC 777 format: \033]777;notify;<title>;<body>\007
OSC_PAYLOAD=$(printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY")

if [ -n "${WARP_CLI_AGENT_IPC:-}" ]; then
    (printf "%s" "$OSC_PAYLOAD" | nc -U "$WARP_CLI_AGENT_IPC") 2>/dev/null || true
else
    # Write directly to /dev/tty to ensure it reaches the terminal.
    (printf "%s" "$OSC_PAYLOAD" > /dev/tty) 2>/dev/null || true
fi
