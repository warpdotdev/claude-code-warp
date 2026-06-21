#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/oz-parent-common.sh"
resolve_hook_state || exit 0
listener_lifecycle_managed_externally && exit 0
ensure_state_dir "$OZ_PARENT_STATE_DIR"

start_listener_if_needed "$SCRIPT_DIR/oz-parent-listener.sh"
