#!/bin/bash
# Builds a structured JSON notification payload for warp://cli-agent.
#
# Usage: source this file, then call build_payload with event-specific fields.
#
# Example:
#   source "$(dirname "${BASH_SOURCE[0]}")/build-payload.sh"
#   BODY=$(build_payload "$INPUT" "stop" \
#       --arg query "$QUERY" \
#       --arg response "$RESPONSE" \
#       --arg transcript_path "$TRANSCRIPT_PATH")
#
# The function extracts common fields (session_id, cwd, project, session_name) from the
# hook's stdin JSON (passed as $1), then merges any extra jq args you pass.

# The current protocol version this plugin knows how to produce.
PLUGIN_CURRENT_PROTOCOL_VERSION=1

# Negotiate the protocol version with Warp.
# Uses min(plugin_current, warp_declared), falling back to 1 if Warp doesn't advertise a version.
negotiate_protocol_version() {
    local warp_version="${WARP_CLI_AGENT_PROTOCOL_VERSION:-1}"
    if [ "$warp_version" -lt "$PLUGIN_CURRENT_PROTOCOL_VERSION" ] 2>/dev/null; then
        echo "$warp_version"
    else
        echo "$PLUGIN_CURRENT_PROTOCOL_VERSION"
    fi
}

# Look up the human-readable session name from Claude Code's session registry.
# Claude Code writes one JSON file per running session to ~/.claude/sessions/
# (keyed by pid) containing sessionId, name, status, etc. The name is kept
# up to date on /rename, so reading it at payload-build time reflects renames.
# Prints an empty string if the registry or session can't be found.
lookup_session_name() {
    local session_id="$1"
    [ -n "$session_id" ] || return 0

    local sessions_dir="${CLAUDE_SESSIONS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions}"
    [ -d "$sessions_dir" ] || return 0

    local files=("$sessions_dir"/*.json)
    [ -e "${files[0]}" ] || return 0

    jq -rs --arg sid "$session_id" \
        '[.[] | select(type == "object" and .sessionId == $sid)] | max_by(.updatedAt // 0) | .name // empty' \
        "${files[@]}" 2>/dev/null
}

build_payload() {
    local input="$1"
    local event="$2"
    shift 2

    local protocol_version
    protocol_version=$(negotiate_protocol_version)

    # Extract common fields from the hook input
    local session_id cwd project session_name
    session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
    cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
    project=""
    if [ -n "$cwd" ]; then
        project=$(basename "$cwd")
    fi
    session_name=$(lookup_session_name "$session_id")

    # Build the payload: common fields + any extra args passed by the caller.
    # Extra args should be jq flag pairs like: --arg key "value" or --argjson key '{"a":1}'
    jq -nc \
        --argjson v "$protocol_version" \
        --arg agent "claude" \
        --arg event "$event" \
        --arg session_id "$session_id" \
        --arg cwd "$cwd" \
        --arg project "$project" \
        --arg session_name "$session_name" \
        "$@" \
        '{v:$v, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project, session_name:$session_name} + $ARGS.named'
}
