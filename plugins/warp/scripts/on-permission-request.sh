#!/bin/bash
# Hook script for Claude Code PermissionRequest event
# Sends a structured Warp notification when Claude needs permission to run a tool

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input from stdin
INPUT=$(cat)

# Extract metadata from the hook input
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
# Fallback to empty object if jq failed or returned empty
[ -z "$TOOL_INPUT" ] && TOOL_INPUT='{}'
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
PROJECT=""
if [ -n "$CWD" ]; then
    PROJECT=$(basename "$CWD")
fi

# Build a human-readable summary for the notification body
TOOL_PREVIEW=$(echo "$INPUT" | jq -r '.tool_input | if .command then .command elif .file_path then .file_path else (tostring | .[0:80]) end // ""' 2>/dev/null)
SUMMARY="Wants to run $TOOL_NAME"
if [ -n "$TOOL_PREVIEW" ]; then
    if [ ${#TOOL_PREVIEW} -gt 120 ]; then
        TOOL_PREVIEW="${TOOL_PREVIEW:0:117}..."
    fi
    SUMMARY="$SUMMARY: $TOOL_PREVIEW"
fi

# Build structured JSON payload
# tool_input is passed as raw JSON (not a string) so Warp can inspect it directly
BODY=$(jq -nc \
    --arg agent "claude" \
    --arg event "permission_request" \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg project "$PROJECT" \
    --arg summary "$SUMMARY" \
    --arg tool_name "$TOOL_NAME" \
    --argjson tool_input "$TOOL_INPUT" \
    '{v:1, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project, summary:$summary, tool_name:$tool_name, tool_input:$tool_input}')

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
