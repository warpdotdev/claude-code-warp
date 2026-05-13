#!/bin/bash
# Emit candidate controlling-tty paths by walking up the process tree.
#
# Background: when the hook runs inside a sandbox that detaches the subprocess
# from its controlling terminal (e.g. Claude Code's macOS `sandbox-exec`
# wrapper for Bash tool calls, when `sandbox.enabled` is set), the hook has
# no controlling terminal — opening `/dev/tty` returns ENXIO. To still deliver
# the OSC notification, we walk up the process tree and emit each ancestor's
# tty device path; the caller tries to write to each in turn until one
# succeeds.
#
# Caveats:
# - We do not verify the ancestor is actually Warp. In nested setups (tmux,
#   screen, ssh into non-Warp), the OSC may end up in a terminal that ignores
#   it. OSC 777 is widely ignored by terminals that don't implement it, so
#   the worst case is a silently dropped notification — not corruption.
# - The walk is depth-limited to bound the number of `ps` invocations.

find_candidate_ttys() {
    local pid=$PPID
    local depth=0
    while [[ -n $pid && $pid != 0 && $pid != 1 && $depth -lt 20 ]]; do
        local tty
        tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
        if [[ -n $tty && $tty != "??" ]]; then
            printf '/dev/%s\n' "$tty"
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        depth=$((depth + 1))
    done
}
