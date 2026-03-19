#!/bin/bash
# Warp notification utility using OSC escape sequences
# Usage: warp-notify.sh <title> <body>
#
# For structured Warp notifications, title should be "warp://cli-agent"
# and body should be a JSON string matching the cli-agent notification schema.

TITLE="${1:-Notification}"
BODY="${2:-}"

# OSC 777 format: \033]777;notify;<title>;<body>\007
# Write directly to /dev/tty to ensure it reaches the terminal
printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY" > /dev/tty 2>/dev/null || true
