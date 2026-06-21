#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/oz-parent-common.sh"
load_hook_state || exit 0
emit_stop_block_if_pending || exit 0
