#!/bin/bash
# Resolve the terminal device to write OSC escape sequences to.
#
# Claude Code spawns hook processes WITHOUT a controlling terminal, so the
# usual `/dev/tty` is unavailable ("Device not configured" / ENXIO) and any
# notification written there is silently dropped. Walk up the process tree
# to find an ancestor (the `claude` process or its parent shell) that still
# has a controlling tty, and return that device node instead.
#
# Falls back to `/dev/tty` when no ancestor with a tty is found, so callers
# behave exactly as before in environments where `/dev/tty` already works.
#
# Usage:
#   source "$SCRIPT_DIR/resolve-tty.sh"
#   printf '...' > "$(resolve_tty_device)"

resolve_tty_device() {
    local pid=$PPID depth=0 tty_name
    while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ "$depth" -lt 25 ]; do
        # `ps -o tty=` prints e.g. `ttys003` (macOS) or `pts/3` (Linux),
        # and `?` / `??` for a process with no controlling terminal.
        tty_name=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d '[:space:]')
        case "$tty_name" in
            '' | '?' | '??')
                : # this ancestor has no controlling tty — keep walking up
                ;;
            *)
                printf '/dev/%s\n' "$tty_name"
                return 0
                ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')
        depth=$((depth + 1))
    done
    printf '/dev/tty\n'
}
