#!/bin/bash
# Hook script for Claude Code Notification event
# Sends a structured Warp notification for Claude Code notification types.
# The event name passed to Warp mirrors notification_type from the hook input
# (e.g. idle_prompt, auth_success) so Warp can route them to distinct UI.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#notification-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Legacy fallback for old Warp versions
if ! should_use_structured; then
    [ "$TERM_PROGRAM" = "WarpTerminal" ] && exec "$SCRIPT_DIR/legacy/on-notification.sh"
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

NOTIF_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"' 2>/dev/null)
MSG=$(echo "$INPUT" | jq -r '.message // "Input needed"' 2>/dev/null)
[ -z "$MSG" ] && MSG="Input needed"
TITLE=$(echo "$INPUT" | jq -r '.title // empty' 2>/dev/null)

BODY=$(build_payload "$INPUT" "$NOTIF_TYPE" \
    --arg summary "$MSG" \
    --arg title "$TITLE")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
