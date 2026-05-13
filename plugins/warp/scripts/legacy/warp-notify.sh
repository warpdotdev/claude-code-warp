#!/bin/bash
# Warp notification utility using OSC escape sequences
# Usage: warp-notify.sh <title> <body>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../find-controlling-tty.sh"

TITLE="${1:-Notification}"
BODY="${2:-}"

# OSC 777 format: \033]777;notify;<title>;<body>\007
emit() {
    printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY" > "$1" 2>/dev/null
}

# Prefer /dev/tty. If unopenable (e.g. the hook is running inside a sandbox
# that detached the subprocess from its controlling terminal), fall back to
# trying each ancestor process's tty in turn until one accepts the write.
emit /dev/tty && exit 0

while read -r tty; do
    emit "$tty" && exit 0
done < <(find_candidate_ttys)

exit 0
