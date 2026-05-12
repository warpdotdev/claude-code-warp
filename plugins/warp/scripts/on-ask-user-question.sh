#!/bin/bash
# Hook script for Claude Code PreToolUse event on AskUserQuestion
# Sends a structured Warp notification when Claude asks the user a question,
# transitioning the session status to Blocked until the user answers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# No legacy equivalent for this hook
if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

# Read hook input from stdin
INPUT=$(cat)

# AskUserQuestion supports 1-4 questions. Surface the first question's text as
# the notification summary; if Claude asks more than one in the same call,
# answering any of them unblocks the session.
SUMMARY=$(echo "$INPUT" | jq -r '.tool_input.questions[0].question // "Claude is asking a question"' 2>/dev/null)

# Truncate for notification display
if [ -n "$SUMMARY" ] && [ ${#SUMMARY} -gt 200 ]; then
    SUMMARY="${SUMMARY:0:197}..."
fi

BODY=$(build_payload "$INPUT" "question_asked" \
    --arg summary "$SUMMARY")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
