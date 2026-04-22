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
# Hook subprocesses spawned by Claude Code lack a controlling terminal,
# so /dev/tty is unavailable. Walk the parent process chain to find the TTY
# that Claude Code is running on (typically within 2-3 levels).
TTY_DEVICE=""
current_pid=$PPID
while [ -n "$current_pid" ] && [ -z "$TTY_DEVICE" ] && [ "$current_pid" != "0" ] && [ "$current_pid" != "1" ]; do
    # Read TTY and PPID in one ps call to minimize process spawns
    read -r tty_val ppid_val < <(ps -o tty=,ppid= -p "$current_pid" 2>/dev/null)
    # Trim whitespace using bash parameter expansion (faster than tr)
    tty_val="${tty_val//[[:space:]]/}"
    if [ -n "$tty_val" ] && [ "$tty_val" != "??" ]; then
        TTY_DEVICE="/dev/$tty_val"
        break
    fi
    # Continue up the process tree
    current_pid="${ppid_val//[[:space:]]/}"
done

# Only send notification if we found a valid TTY device
if [ -n "$TTY_DEVICE" ] && [ -w "$TTY_DEVICE" ]; then
    printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY" > "$TTY_DEVICE" 2>/dev/null || true
fi
