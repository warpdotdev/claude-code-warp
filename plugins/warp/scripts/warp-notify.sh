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
# Hook subprocesses spawned by Claude Code may lack a controlling terminal,
# so /dev/tty is unavailable. Walk the parent process chain to find the actual
# TTY device and write there instead.
TTY_DEVICE=""
current_pid=$PPID
for _ in 1 2 3 4 5; do
    t=$(ps -o tty= -p "$current_pid" 2>/dev/null | tr -d ' ')
    if [ -n "$t" ] && [ "$t" != "??" ]; then
        TTY_DEVICE="/dev/$t"
        break
    fi
    current_pid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')
    [ -z "$current_pid" ] && break
done

printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY" > "${TTY_DEVICE:-/dev/tty}" 2>/dev/null || true

# Fallback to macOS notification center if OSC didn't work or for Warp versions
# that don't support OSC 777 yet
if command -v osascript &>/dev/null; then
    # Parse JSON body to extract summary for macOS notification
    SUMMARY=$(echo "$BODY" | jq -r '.summary // .event // "Claude Code"' 2>/dev/null)
    PROJECT=$(echo "$BODY" | jq -r '.project // "Claude"' 2>/dev/null)
    osascript -e "display notification \"$SUMMARY\" with title \"$PROJECT\" subtitle \"Claude Code\"" &>/dev/null || true
fi
