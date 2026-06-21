#!/bin/bash

set -euo pipefail

HOOK_EVENT="${1:?hook event name is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/oz-parent-common.sh"
load_hook_state || exit 0
STATE_DIR="$(hook_state_dir)"

if listener_lifecycle_managed_externally; then
    emit_driver_hook_additional_context "$HOOK_EVENT" "$STATE_DIR" || exit 0
    acknowledge_driver_hook_output "$STATE_DIR"
    exit 0
fi

MAX_CONTEXT_CHARS="${OZ_PARENT_MAX_CONTEXT_CHARS:-6000}"
build_parent_context_from_staged_messages "$STATE_DIR" "$MAX_CONTEXT_CHARS" || exit 0
deliver_and_remove_staged_messages "$STATE_DIR" "${OZ_PARENT_SURFACED_IDS[@]}"
emit_hook_additional_context "$HOOK_EVENT" "$OZ_PARENT_RENDERED_CONTEXT"
