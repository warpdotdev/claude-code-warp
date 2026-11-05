#!/bin/bash
# Decides whether the current turn should reach Warp at all.
#
# Claude Code starts turns of its own: a teammate or another session sends a message,
# a channel delivers an event, a background task reports back. None of these is the
# user's task finishing, so they send no prompt_submit, tool_complete, stop or
# idle_prompt to Warp.
#
# A turn Warp was told about stays reported to the end, so its status never sticks:
# once prompt_submit or permission_request was sent for a turn, its stop is sent too.
#
# The origin is read from the transcript (turnOrigin / origin.kind; Agent Teams messages
# carry neither and are matched by their prefix). The transcript is scanned
# incrementally: the byte offset, the last turn origin and the engaged flag are cached
# per session, so each hook reads only the new bytes.
#
# Usage:
#   source "$SCRIPT_DIR/turn-origin.sh"
#   turn_is_silent "$INPUT" && exit 0
#   turn_prompt_is_injected "$INPUT" && exit 0
#   turn_mark_engaged "$INPUT"
#   turn_end "$INPUT"

TURN_STATE_DIR="${TURN_STATE_DIR:-${TMPDIR:-/tmp}/claude-code-warp-turns}"

# Prompt prefixes of the turns Claude Code injects: Agent Teams and cross-session
# messages, channel events, background task reports.
TURN_INJECTED_PREFIX='^(Another Claude session sent a message|<channel[ >]|<task-notification>|<teammate-message[ >]|<cross-session-message[ >])'

_turn_state_file() {
    local session_id
    session_id=$(echo "$1" | jq -r '.session_id // empty' 2>/dev/null)
    [ -z "$session_id" ] && return 1
    echo "$TURN_STATE_DIR/$session_id"
}

_turn_write_state() {
    mkdir -p "$TURN_STATE_DIR" 2>/dev/null
    echo "$2 $3 $4" > "$1" 2>/dev/null
}

# Prints "<origin> <engaged>" for the current turn after scanning new transcript bytes.
_turn_scan() {
    local input="$1" state transcript offset=0 origin="" engaged=0 size latest
    state=$(_turn_state_file "$input") || return 1
    [ -f "$state" ] && read -r offset origin engaged < "$state"
    transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
    if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
        echo "unknown ${engaged:-0}"
        return 0
    fi

    size=$(wc -c < "$transcript" | tr -d ' ')
    [ "${offset:-0}" -gt "$size" ] 2>/dev/null && { offset=0; origin=""; }

    latest=$(tail -c +"$((${offset:-0} + 1))" "$transcript" 2>/dev/null \
        | grep -E '"turnOrigin"|"origin"|"queued_command"|Another Claude session sent a message' \
        | jq -Rr '
            fromjson? |
            if .type == "attachment" and .attachment.type == "queued_command" then
                # A prompt the user typed mid-turn makes the turn theirs; a queued channel event does not.
                if ((.attachment.origin // .origin).kind // "human") == "human" then "human" else empty end
            elif .type == "user" and (.isMeta | not) then
                (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end) as $text |
                if (.turnOrigin // .origin.kind) then (.turnOrigin // .origin.kind)
                elif ($text | startswith("Another Claude session sent a message")) then "peer"
                else empty end
            else empty end' 2>/dev/null \
        | tail -1)
    [ -n "$latest" ] && origin="$latest"

    # A half-written last line is rescanned next time rather than skipped.
    [ "$(tail -c 1 "$transcript" | od -An -c | tr -d ' ')" = '\n' ] || size="${offset:-0}"

    _turn_write_state "$state" "$size" "${origin:-unknown}" "${engaged:-0}"
    echo "${origin:-unknown} ${engaged:-0}"
}

# Returns 0 when Warp should not hear about this turn.
turn_is_silent() {
    local origin engaged
    read -r origin engaged < <(_turn_scan "$1") || return 1
    [ "$origin" != "human" ] && [ "$origin" != "unknown" ] && [ "$engaged" != "1" ]
}

# Returns 0 when UserPromptSubmit fired for a turn Claude Code injected.
turn_prompt_is_injected() {
    echo "$1" | jq -e --arg re "$TURN_INJECTED_PREFIX" '(.prompt // "") | test($re)' > /dev/null 2>&1
}

# The user has been told about this turn or has to act in it, so its stop must be sent.
turn_mark_engaged() {
    local state origin size
    state=$(_turn_state_file "$1") || return 0
    read -r origin _ < <(_turn_scan "$1") || return 0
    read -r size _ < "$state" 2>/dev/null
    _turn_write_state "$state" "${size:-0}" "$origin" 1
}

turn_end() {
    local state offset origin
    state=$(_turn_state_file "$1") || return 0
    [ -f "$state" ] || return 0
    read -r offset origin _ < "$state"
    _turn_write_state "$state" "$offset" "$origin" 0
}
