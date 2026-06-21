#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/oz-parent-common.sh"

STATE_DIR="${1:?state directory is required}"

stage_message_from_watch_record() {
    local state_dir="$1"
    local line="$2"
    local sequence message_id target

    sequence="$(json_field "$line" '.sequence')"
    message_id="$(json_field "$line" '.message_id')"

    [ -n "$sequence" ] || return 0
    [ -n "$message_id" ] || return 0

    target="$(staged_message_path "$state_dir" "$sequence" "$message_id")"
    if [ ! -f "$target" ]; then
        printf '%s\n' "$line" >"$target"
    fi

    printf '%s\n' "$sequence" >"$(last_sequence_file "$state_dir")"
}

ensure_state_dir "$STATE_DIR"
ensure_last_sequence_file "$STATE_DIR"
LAST_SEQUENCE="$(cat "$(last_sequence_file "$STATE_DIR")" 2>/dev/null || true)"
[ -n "$LAST_SEQUENCE" ] || LAST_SEQUENCE=0

"$OZ_CLI" run message watch "$OZ_RUN_ID" --since-sequence "$LAST_SEQUENCE" --output-format ndjson |
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        stage_message_from_watch_record "$STATE_DIR" "$line"
    done
