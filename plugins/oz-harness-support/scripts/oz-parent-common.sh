#!/bin/bash

set -euo pipefail

OZ_PARENT_HOOK_INPUT=""
OZ_PARENT_STATE_DIR=""
OZ_PARENT_RENDERED_CONTEXT=""
OZ_PARENT_REMAINING_COUNT=0
OZ_PARENT_SURFACED_IDS=()

read_hook_input() {
    cat
}
# Only child Claude runs have a lead-agent parent to bridge messages from.
# When OZ_PARENT_RUN_ID is absent, leave the hooks inert so they do not affect
# regular Oz harness sessions that are not running as child agents.

oz_harness_available() {
    [ -n "${OZ_CLI:-}" ] &&
        [ -n "${OZ_RUN_ID:-}" ] &&
        [ -n "${OZ_PARENT_RUN_ID:-}" ] &&
        command -v "$OZ_CLI" >/dev/null 2>&1
}

json_field() {
    local input="$1"
    local query="$2"
    printf '%s' "$input" | jq -r "$query // empty" 2>/dev/null
}

json_file_field() {
    local path="$1"
    local query="$2"
    jq -r "$query // empty" "$path" 2>/dev/null
}

session_id_from_input() {
    json_field "$1" '.session_id'
}

state_root() {
    printf '%s\n' "${OZ_PARENT_STATE_ROOT:-$HOME/.claude-code/oz-parent-bridge}"
}

state_dir_from_session_id() {
    local session_id="$1"
    printf '%s/%s\n' "$(state_root)" "$session_id"
}

state_dir_from_input() {
    local session_id
    session_id=$(session_id_from_input "$1")
    [ -n "$session_id" ] || return 1
    state_dir_from_session_id "$session_id"
}

ensure_state_dir() {
    local state_dir="$1"
    mkdir -p "$state_dir/staged"
}

staged_dir() {
    local state_dir="$1"
    printf '%s/staged\n' "$state_dir"
}
surfaced_dir() {
    local state_dir="$1"
    printf '%s/surfaced\n' "$state_dir"
}

hook_output_file() {
    local state_dir="$1"
    printf '%s/pending-hook-output.json\n' "$state_dir"
}

hook_output_ack_file() {
    local state_dir="$1"
    printf '%s/pending-hook-output.ack\n' "$state_dir"
}

listener_pid_file() {
    local state_dir="$1"
    printf '%s/listener.pid\n' "$state_dir"
}

listener_log_file() {
    local state_dir="$1"
    printf '%s/listener.log\n' "$state_dir"
}

last_sequence_file() {
    local state_dir="$1"
    printf '%s/last-sequence\n' "$state_dir"
}

staged_message_path() {
    local state_dir="$1"
    local sequence="$2"
    local message_id="$3"
    printf '%s/%020d-%s.json\n' "$(staged_dir "$state_dir")" "$sequence" "$message_id"
}

sorted_staged_messages() {
    local state_dir="$1"
    local dir
    dir=$(staged_dir "$state_dir")
    [ -d "$dir" ] || return 0
    find "$dir" -type f -name '*.json' -print | sort
}
sorted_surfaced_messages() {
    local state_dir="$1"
    local dir
    dir=$(surfaced_dir "$state_dir")
    [ -d "$dir" ] || return 0
    find "$dir" -type f -name '*.json' -print | sort
}

staged_message_count() {
    local state_dir="$1"
    sorted_staged_messages "$state_dir" | wc -l | tr -d ' '
}
surfaced_message_count() {
    local state_dir="$1"
    sorted_surfaced_messages "$state_dir" | wc -l | tr -d ' '
}

driver_hook_output_available() {
    local state_dir="$1"
    [ -f "$(hook_output_file "$state_dir")" ] &&
        [ ! -f "$(hook_output_ack_file "$state_dir")" ]
}

wait_for_driver_hook_output() {
    local state_dir="$1"
    local attempt

    for ((attempt = 0; attempt < 40; attempt++)); do
        if driver_hook_output_available "$state_dir"; then
            return 0
        fi
        if [ -f "$(hook_output_ack_file "$state_dir")" ]; then
            return 1
        fi
        sleep 0.05
    done

    driver_hook_output_available "$state_dir"
}

emit_driver_hook_additional_context() {
    local hook_event="$1"
    local state_dir="${2:-$OZ_PARENT_STATE_DIR}"
    local output_file additional_context

    wait_for_driver_hook_output "$state_dir" || return 1
    output_file=$(hook_output_file "$state_dir")
    additional_context=$(json_file_field "$output_file" '.additional_context')
    [ -n "$additional_context" ] || return 1
    emit_hook_additional_context "$hook_event" "$additional_context"
}

acknowledge_driver_hook_output() {
    local state_dir="${1:-$OZ_PARENT_STATE_DIR}"
    : >"$(hook_output_ack_file "$state_dir")"
}

driver_pending_parent_message_count() {
    local state_dir="$1"
    local pending_count surfaced_count

    pending_count="$(staged_message_count "$state_dir")"
    if [ ! -f "$(hook_output_ack_file "$state_dir")" ]; then
        surfaced_count="$(surfaced_message_count "$state_dir")"
        pending_count=$((pending_count + surfaced_count))
    fi

    printf '%s\n' "$pending_count"
}

pending_parent_message_count() {
    local state_dir="$1"
    if listener_lifecycle_managed_externally; then
        driver_pending_parent_message_count "$state_dir"
    else
        staged_message_count "$state_dir"
    fi
}

# The driver-owned bridge can stage a parent message just after Claude emits
# Stop. Keep polling for a short window so late-arriving parent work still
# blocks completion instead of letting the child exit too early.

stop_linger_attempts() {
    local attempts="${OZ_PARENT_STOP_LINGER_ATTEMPTS:-240}"
    if ! [[ "$attempts" =~ ^[0-9]+$ ]]; then
        attempts=240
    fi
    printf '%s\n' "$attempts"
}

stop_linger_poll_seconds() {
    local poll_seconds="${OZ_PARENT_STOP_LINGER_POLL_SECONDS:-0.25}"
    if ! [[ "$poll_seconds" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]; then
        poll_seconds="0.25"
    fi
    printf '%s\n' "$poll_seconds"
}

# Poll the pending-message count instead of sampling it only once. This gives
# the bridge time to finish writing newly arrived parent messages into the
# session state before the stop hook decides whether to block completion.

wait_for_pending_parent_messages() {
    local state_dir="$1"
    local attempts poll_seconds attempt pending_count

    attempts="$(stop_linger_attempts)"
    poll_seconds="$(stop_linger_poll_seconds)"

    for ((attempt = 0; attempt <= attempts; attempt++)); do
        pending_count="$(pending_parent_message_count "$state_dir")"
        if [ "$pending_count" -gt 0 ]; then
            printf '%s\n' "$pending_count"
            return 0
        fi

        [ "$attempt" -lt "$attempts" ] || break
        sleep "$poll_seconds"
    done

    return 1
}

listener_running() {
    local state_dir="$1"
    local pid_file pid
    pid_file=$(listener_pid_file "$state_dir")
    [ -f "$pid_file" ] || return 1
    pid=$(cat "$pid_file" 2>/dev/null || true)
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null
}

kill_listener() {
    local state_dir="$1"
    local pid_file pid
    pid_file=$(listener_pid_file "$state_dir")
    [ -f "$pid_file" ] || return 0
    pid=$(cat "$pid_file" 2>/dev/null || true)
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
}

ensure_last_sequence_file() {
    local state_dir="$1"
    local path
    path=$(last_sequence_file "$state_dir")
    [ -f "$path" ] || : >"$path"
}

# Set by the Warp Rust driver when it owns the parent-bridge listener and
# surfaces hook output itself. In that mode the shell hooks should reuse the
# driver's state directory instead of starting or cleaning up their own
# listener lifecycle.
listener_lifecycle_managed_externally() {
    [ "${OZ_PARENT_LISTENER_MANAGED_EXTERNALLY:-0}" = "1" ]
}

load_hook_state() {
    resolve_hook_state || return 1
    if listener_lifecycle_managed_externally; then
        [ -d "$OZ_PARENT_STATE_DIR" ] || return 1
    else
        ensure_state_dir "$OZ_PARENT_STATE_DIR"
    fi
}

resolve_hook_state() {
    OZ_PARENT_HOOK_INPUT="$(read_hook_input)"
    oz_harness_available || return 1

    OZ_PARENT_STATE_DIR="$(state_dir_from_input "$OZ_PARENT_HOOK_INPUT" || true)"
    [ -n "$OZ_PARENT_STATE_DIR" ] || return 1
}

hook_state_dir() {
    printf '%s\n' "$OZ_PARENT_STATE_DIR"
}

start_listener_if_needed() {
    local listener_script="$1"
    local state_dir="${2:-$OZ_PARENT_STATE_DIR}"

    listener_running "$state_dir" && return 0

    kill_listener "$state_dir"
    nohup "$listener_script" "$state_dir" \
        >>"$(listener_log_file "$state_dir")" 2>&1 &
    printf '%s\n' "$!" >"$(listener_pid_file "$state_dir")"
}

cleanup_hook_state() {
    local state_dir="${1:-$OZ_PARENT_STATE_DIR}"
    kill_listener "$state_dir"
    rm -rf "$state_dir"
}

emit_stop_block_if_pending() {
    local state_dir="${1:-$OZ_PARENT_STATE_DIR}"
    local pending_count reason

    # Re-check during the linger window so a parent message that arrives right
    # after Stop can still keep the child alive until the next safe hook drain.
    pending_count="$(wait_for_pending_parent_messages "$state_dir")" || return 1
    [ "$pending_count" -gt 0 ] || return 1

    reason="There are ${pending_count} pending parent message(s) from the lead Oz run. Continue so the next safe boundary can surface them."
    jq -nc --arg reason "$reason" '{decision:"block", reason:$reason}'
}

mark_message_delivered() {
    local message_id="$1"
    "$OZ_CLI" run message mark-delivered "$message_id" >/dev/null 2>&1 ||
        "$OZ_CLI" run message delivered "$message_id" >/dev/null 2>&1 ||
        true
}

remove_staged_message() {
    local state_dir="$1"
    local message_id="$2"
    find "$(staged_dir "$state_dir")" -type f -name "*-${message_id}.json" -delete 2>/dev/null || true
}

build_parent_context_from_staged_messages() {
    local state_dir="$1"
    local max_context_chars="${2:-6000}"
    local staged_file total_staged=0
    local message_id sender_run_id subject body sequence
    local block separator candidate remaining note

    OZ_PARENT_RENDERED_CONTEXT=$'Lead-agent updates arrived from Oz. Treat the latest parent instructions below as authoritative.\n'
    OZ_PARENT_REMAINING_COUNT=0
    OZ_PARENT_SURFACED_IDS=()

    while IFS= read -r staged_file; do
        [ -n "$staged_file" ] || continue
        total_staged=$((total_staged + 1))

        message_id="$(json_file_field "$staged_file" '.message_id')"
        sender_run_id="$(json_file_field "$staged_file" '.sender_run_id')"
        subject="$(json_file_field "$staged_file" '.subject')"
        body="$(json_file_field "$staged_file" '.body')"
        sequence="$(json_file_field "$staged_file" '.sequence')"

        [ -n "$message_id" ] || continue
        [ -n "$subject" ] || subject="(no subject)"

        block=$'---\nParent message'
        if [ -n "$sequence" ]; then
            block="$block #$sequence"
        fi
        if [ -n "$sender_run_id" ]; then
            block="$block from $sender_run_id"
        fi
        block="$block"$'\n'"Subject: $subject"$'\n\n'"$body"

        separator=""
        if [ "${#OZ_PARENT_SURFACED_IDS[@]}" -gt 0 ]; then
            separator=$'\n\n'
        fi

        candidate="${OZ_PARENT_RENDERED_CONTEXT}${separator}${block}"
        if [ "${#candidate}" -gt "$max_context_chars" ]; then
            remaining=$((max_context_chars - ${#OZ_PARENT_RENDERED_CONTEXT} - ${#separator}))
            if [ "$remaining" -le 3 ] && [ "${#OZ_PARENT_SURFACED_IDS[@]}" -gt 0 ]; then
                break
            fi
            if [ "$remaining" -gt 3 ] && [ "${#block}" -gt "$remaining" ]; then
                block="${block:0:$((remaining - 3))}..."
            elif [ "${#OZ_PARENT_SURFACED_IDS[@]}" -gt 0 ]; then
                break
            fi
        fi

        OZ_PARENT_RENDERED_CONTEXT="${OZ_PARENT_RENDERED_CONTEXT}${separator}${block}"
        OZ_PARENT_SURFACED_IDS+=("$message_id")
    done < <(sorted_staged_messages "$state_dir")

    [ "${#OZ_PARENT_SURFACED_IDS[@]}" -gt 0 ] || return 1

    OZ_PARENT_REMAINING_COUNT=$((total_staged - ${#OZ_PARENT_SURFACED_IDS[@]}))
    if [ "$OZ_PARENT_REMAINING_COUNT" -gt 0 ]; then
        note=$'\n\nMore parent messages are still staged and will be surfaced on a later turn.'
        if [ $(( ${#OZ_PARENT_RENDERED_CONTEXT} + ${#note} )) -le "$max_context_chars" ]; then
            OZ_PARENT_RENDERED_CONTEXT="${OZ_PARENT_RENDERED_CONTEXT}${note}"
        fi
    fi
}

deliver_and_remove_staged_messages() {
    local state_dir="$1"
    local message_id
    shift

    for message_id in "$@"; do
        mark_message_delivered "$message_id"
        remove_staged_message "$state_dir" "$message_id"
    done
}

emit_hook_additional_context() {
    local hook_event="$1"
    local additional_context="${2:-$OZ_PARENT_RENDERED_CONTEXT}"

    jq -nc \
        --arg event "$hook_event" \
        --arg ctx "$additional_context" \
        '{hookSpecificOutput:{hookEventName:$event, additionalContext:$ctx}}'
}
