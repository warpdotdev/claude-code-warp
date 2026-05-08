#!/bin/bash
# Warp notification utility using OSC escape sequences
# Usage: warp-notify.sh <title> <body>
#
# The write to /dev/tty is bounded by WARP_NOTIFY_TIMEOUT_SEC (default 2)
# so an unresponsive Warp UI cannot block the caller indefinitely.

TITLE="${1:-Notification}"
BODY="${2:-}"
TARGET="${WARP_NOTIFY_TARGET:-/dev/tty}"
TIMEOUT_SEC="${WARP_NOTIFY_TIMEOUT_SEC:-2}"

# OSC 777 format: \033]777;notify;<title>;<body>\007
SEQ=$(printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY")

{
    printf '%s' "$SEQ" > "$TARGET" 2>/dev/null
} &
writer_pid=$!

{
    sleep "$TIMEOUT_SEC" 2>/dev/null
    kill -KILL "$writer_pid" 2>/dev/null
} &
watchdog_pid=$!

wait "$writer_pid" 2>/dev/null

kill -KILL "$watchdog_pid" 2>/dev/null
wait "$watchdog_pid" 2>/dev/null

exit 0
