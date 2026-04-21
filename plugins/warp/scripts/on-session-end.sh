#!/bin/bash
# Hook script for Claude Code SessionEnd event
# Emits session_end so Warp can archive the sidebar entry instead of leaving
# it stuck in its last known state (done / running / blocked) after termination.
#
# Also cleans up per-session temp files written by on-prompt-submit.sh.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#sessionend

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

# reason: "clear", "resume", "logout", "prompt_input_exit",
#         "bypass_permissions_disabled", "other"
REASON=$(echo "$INPUT" | jq -r '.reason // "other"' 2>/dev/null)

BODY=$(build_payload "$INPUT" "session_end" \
    --arg reason "$REASON")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"

# Housekeeping: remove the per-session query file written by on-prompt-submit.sh
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
    rm -f "${TMPDIR:-/tmp}/warp-claude-${SESSION_ID}".* 2>/dev/null || true
fi
