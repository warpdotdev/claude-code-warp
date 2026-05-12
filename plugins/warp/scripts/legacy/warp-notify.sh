#!/bin/bash
# Warp notification utility using OSC escape sequences
# Usage: warp-notify.sh <title> <body>

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
