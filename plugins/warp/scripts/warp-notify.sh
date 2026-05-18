#!/bin/bash
# Warp notification utility using OSC escape sequences
# Usage: warp-notify.sh <title> <body>
#
# For structured Warp notifications, title should be "warp://cli-agent"
# and body should be a JSON string matching the cli-agent notification schema.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"
source "$SCRIPT_DIR/resolve-tty.sh"

# Only emit notifications when we've confirmed the Warp build can render them.
if ! should_use_structured; then
    exit 0
fi

TITLE="${1:-Notification}"
BODY="${2:-}"

# OSC 777 format: \033]777;notify;<title>;<body>\007
# Hook processes have no controlling terminal, so resolve the real tty of an
# ancestor process rather than relying on /dev/tty (which fails in that case).
printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY" > "$(resolve_tty_device)" 2>/dev/null || true
