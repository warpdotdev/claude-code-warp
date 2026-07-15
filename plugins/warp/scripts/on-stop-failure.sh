#!/bin/bash
# Hook script for Claude Code StopFailure event
# Sends a structured Warp notification when Claude's turn ends due to an API error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Legacy Warp clients that don't support structured events don't get a
# stop_failure notification — they have no UI to act on it.
if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

# Read hook input from stdin
INPUT=$(cat)

# Try to extract an error message from the hook input.
# Claude Code may surface the error under different field names depending on
# the version, so check the most likely candidates.
ERROR_MESSAGE=$(echo "$INPUT" | jq -r '
    .error_message // .error // .message // empty
' 2>/dev/null)

# Also try to extract the last user query from the transcript so Warp can
# show it as the notification title, matching the Stop hook behaviour.
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
QUERY=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    QUERY=$(jq -rs '
        [
            .[] | select(.type == "user") |
            if .message.content | type == "string" then .
            elif [.message.content[] | select(.type == "text")] | length > 0 then .
            else empty
            end
        ] | last |
        if .message.content | type == "array"
        then [.message.content[] | select(.type == "text") | .text] | join(" ")
        else .message.content // empty
        end
    ' "$TRANSCRIPT_PATH" 2>/dev/null)

    if [ -n "$QUERY" ] && [ ${#QUERY} -gt 200 ]; then
        QUERY="${QUERY:0:197}..."
    fi
fi

BODY=$(build_payload "$INPUT" "stop_failure" \
    --arg query "$QUERY" \
    --arg response "$ERROR_MESSAGE" \
    --arg transcript_path "$TRANSCRIPT_PATH")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
