#!/bin/bash
# Hook script for Claude Code PermissionDenied event
# Fires when the auto-mode classifier silently denies a tool call. Without this
# hook, any prior permission_request that the classifier then denies leaves the
# sidebar stuck on "blocked-awaiting-permission" until the next Stop.
#
# Only fires in auto mode (--dangerously-skip-permissions,
# --permission-mode auto, etc). Manual denials do not fire this event.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#permissiondenied-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
[ -z "$TOOL_INPUT" ] && TOOL_INPUT='{}'
REASON=$(echo "$INPUT" | jq -r '.reason // "denied by auto mode classifier"' 2>/dev/null)

# Mirror the permission_request summary format so the sidebar renders
# consistently — "Auto-denied Bash: rm -rf /tmp".
TOOL_PREVIEW=$(echo "$INPUT" | jq -r '(.tool_input | if .command then .command elif .file_path then .file_path elif .url then .url elif .query then .query elif .pattern then .pattern else (tostring | .[0:80]) end) // ""' 2>/dev/null)
SUMMARY="Auto-denied $TOOL_NAME"
if [ -n "$TOOL_PREVIEW" ]; then
    if [ ${#TOOL_PREVIEW} -gt 120 ]; then
        TOOL_PREVIEW="${TOOL_PREVIEW:0:117}..."
    fi
    SUMMARY="$SUMMARY: $TOOL_PREVIEW"
fi

BODY=$(build_payload "$INPUT" "permission_denied" \
    --arg summary "$SUMMARY" \
    --arg tool_name "$TOOL_NAME" \
    --argjson tool_input "$TOOL_INPUT" \
    --arg reason "$REASON")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
