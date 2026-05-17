#!/bin/bash
# Warp notification utility using OSC escape sequences
# Usage: warp-notify.sh <title> <body>
#
# For structured Warp notifications, title should be "warp://cli-agent"
# and body should be a JSON string matching the cli-agent notification schema.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Only emit notifications when we've confirmed the Warp build can render them.
if ! should_use_structured; then
    exit 0
fi

TITLE="${1:-Notification}"
BODY="${2:-}"

# OSC 777 format: \033]777;notify;<title>;<body>\007
# Try /dev/tty first (macOS/Linux). On Windows, /dev/tty fails inside
# Claude Code's hook runner because stdio is captured. Fall back to stderr.
if printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY" > /dev/tty 2>/dev/null; then
    exit 0
fi

# Last resort: stderr (may not reach terminal in sandboxed hook contexts)
printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY" >&2 2>/dev/null || true
