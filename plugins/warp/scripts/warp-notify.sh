#!/bin/bash
# Warp notification utility using OSC escape sequences
# Usage: warp-notify.sh <title> <body>
#
# For structured Warp notifications, title should be "warp://cli-agent"
# and body should be a JSON string matching the cli-agent notification schema.
#
# The write to /dev/tty is bounded by WARP_NOTIFY_TIMEOUT_SEC (default 2).
# Without this bound, an unresponsive Warp UI — which leaves the controlling
# TTY's output buffer undrained — would block the calling Claude Code session
# indefinitely. Tests can redirect output via WARP_NOTIFY_TARGET.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Only emit notifications when we've confirmed the Warp build can render them.
if ! should_use_structured; then
    exit 0
fi

TITLE="${1:-Notification}"
BODY="${2:-}"
TARGET="${WARP_NOTIFY_TARGET:-/dev/tty}"
TIMEOUT_SEC="${WARP_NOTIFY_TIMEOUT_SEC:-2}"

# OSC 777 format: \033]777;notify;<title>;<body>\007
SEQ=$(printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY")

# Spawn the writer in the background. If the target's output buffer is full
# and not draining (e.g. Warp UI hung), the open()/write() would otherwise
# block forever; the watchdog below caps that to TIMEOUT_SEC.
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

# Tear down the watchdog (no-op if it already fired).
kill -KILL "$watchdog_pid" 2>/dev/null
wait "$watchdog_pid" 2>/dev/null

# Notifications are best-effort; never propagate failure to the caller.
exit 0
