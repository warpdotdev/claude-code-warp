#!/bin/bash
# Hook script for Claude Code Notification event (idle_prompt only)
# Sends a structured Warp notification when Claude has been idle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input from stdin
INPUT=$(cat)

# Extract metadata from the hook input
NOTIF_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
MSG=$(echo "$INPUT" | jq -r '.message // "Input needed"' 2>/dev/null)
[ -z "$MSG" ] && MSG="Input needed"
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
PROJECT=""
if [ -n "$CWD" ]; then
    PROJECT=$(basename "$CWD")
fi

# Build structured JSON payload
BODY=$(jq -nc \
    --arg agent "claude" \
    --arg event "$NOTIF_TYPE" \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg project "$PROJECT" \
    --arg summary "$MSG" \
    '{v:1, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project, summary:$summary}')

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
