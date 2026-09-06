#!/bin/bash
# Determines whether the Claude Code session still has background work in flight.
#
# Claude Code (>= 2.1.145) includes a `background_tasks` array in Stop hook
# input listing in-flight sub-agents, background shells, monitors, workflows
# and teammates. The main agent's turn ends (firing Stop) while those keep
# running, and the harness re-invokes the main agent — firing Stop again —
# each time one of them completes. Only the Stop with nothing left running is
# a real "task complete".
#
# Usage:
#   source "$SCRIPT_DIR/has-background-work.sh"
#   if has_background_work "$INPUT"; then
#       exit 0   # not done yet — a later Stop will fire when the work finishes
#   fi
#
# Returns 0 (true) when at least one background task is still running,
# 1 (false) otherwise. On older Claude Code the field is absent, so this
# returns false and behaviour is unchanged. Only `status == "running"` counts,
# so an unfamiliar status fails open toward notifying rather than staying silent.
has_background_work() {
    local input="$1"
    local running
    running=$(echo "$input" | jq -r '
        [.background_tasks[]? | select(.status == "running")] | length
    ' 2>/dev/null)
    [ "${running:-0}" -gt 0 ] 2>/dev/null
}
