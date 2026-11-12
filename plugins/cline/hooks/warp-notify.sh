#!/bin/bash
# Shared helpers for the Cline hook scripts. Sourced by each hook; Cline only
# runs files named after a hook event, so this file is never invoked directly.
#
# Cline pipes a JSON payload to each hook on stdin. The fields read here are
# common to every hook event: taskId, workspaceRoots and workspaceInfo.

# Last known Warp releases per channel that advertised
# WARP_CLI_AGENT_PROTOCOL_VERSION but couldn't render structured
# notifications. Keep in sync with plugins/warp/scripts/should-use-structured.sh.
LAST_BROKEN_STABLE="v0.2026.03.25.08.24.stable_05"
LAST_BROKEN_PREVIEW="v0.2026.03.25.08.24.preview_05"

should_use_structured() {
    [ -z "${WARP_CLI_AGENT_PROTOCOL_VERSION:-}" ] && return 1
    [ -z "${WARP_CLIENT_VERSION:-}" ] && return 1

    local threshold=""
    case "$WARP_CLIENT_VERSION" in
        *stable*)  threshold="$LAST_BROKEN_STABLE" ;;
        *preview*) threshold="$LAST_BROKEN_PREVIEW" ;;
    esac
    if [ -n "$threshold" ] && [[ ! "$WARP_CLIENT_VERSION" > "$threshold" ]]; then
        return 1
    fi
    return 0
}

# Reads the hook payload from stdin and sets INPUT, SESSION_ID, CWD and PROJECT.
read_hook_input() {
    INPUT=$(cat 2>/dev/null)
    [ -z "$INPUT" ] && INPUT='{}'
    SESSION_ID=$(echo "$INPUT" | jq -r '.taskId // "unknown"' 2>/dev/null)
    CWD=$(echo "$INPUT" | jq -r '.workspaceInfo.rootPath // .workspaceRoots[0] // empty' 2>/dev/null)
    [ -z "$CWD" ] && CWD="$(pwd)"
    PROJECT=$(basename "$CWD")
}

# Truncates $1 to 200 characters for notification display.
truncate_text() {
    local text="$1"
    if [ ${#text} -gt 200 ]; then
        text="${text:0:197}..."
    fi
    printf '%s' "$text"
}

# Emits a structured Warp notification with the given JSON body. The group
# redirect keeps a missing controlling terminal from printing an error.
warp_notify() {
    { printf '\033]777;notify;%s;%s\007' "warp://cli-agent" "$1" > /dev/tty; } 2>/dev/null || true
}
