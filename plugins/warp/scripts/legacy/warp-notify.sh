#!/bin/bash
# Warp notification utility using OSC escape sequences
# Usage: warp-notify.sh <title> <body>

TITLE="${1:-Notification}"
BODY="${2:-}"

# OSC 777 format: \033]777;notify;<title>;<body>\007
# Write to /dev/tty when one is usable. MSYS2 has a /dev/tty node that cannot be
# opened on a detached process, so probe first; stderr is redirected before the
# open (left-to-right) so the ENXIO error cannot leak either way.
if [ -e /dev/tty ] && { : > /dev/tty; } 2>/dev/null; then
    printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY" 2>/dev/null > /dev/tty || true
fi
