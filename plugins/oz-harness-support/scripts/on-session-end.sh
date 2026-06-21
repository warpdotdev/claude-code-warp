#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/oz-parent-common.sh"
resolve_hook_state || exit 0
listener_lifecycle_managed_externally && exit 0

cleanup_hook_state
