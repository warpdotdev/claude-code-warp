#!/bin/bash
# Hook script for Claude Code Stop event
# Sends a Warp notification when Claude completes a task

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input from stdin
INPUT=$(cat)

# Extract transcript path from the hook input
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# Default message
MSG="Task completed"

# Try to extract prompt and response from the transcript (JSONL format)
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Get the first user prompt
    PROMPT=$(jq -rs '
        [.[] | select(.type == "user")] | first |
        [.message.content[] | select(.type == "text") | .text] | join(" ")
    ' "$TRANSCRIPT_PATH" 2>/dev/null)
    
    # Get the last assistant response
    RESPONSE=$(jq -rs '
        [.[] | select(.type == "assistant" and .message.content)] | last |
        [.message.content[] | select(.type == "text") | .text] | join(" ")
    ' "$TRANSCRIPT_PATH" 2>/dev/null)
    
    if [ -n "$PROMPT" ] && [ -n "$RESPONSE" ]; then
        # Truncate prompt to 50 chars
        if [ ${#PROMPT} -gt 50 ]; then
            PROMPT="${PROMPT:0:47}..."
        fi
        # Truncate response to 120 chars
        if [ ${#RESPONSE} -gt 120 ]; then
            RESPONSE="${RESPONSE:0:117}..."
        fi
        MSG="\"${PROMPT}\" → ${RESPONSE}"
    elif [ -n "$RESPONSE" ]; then
        # Fallback to just response if no prompt found
        if [ ${#RESPONSE} -gt 175 ]; then
            RESPONSE="${RESPONSE:0:172}..."
        fi
        MSG="$RESPONSE"
    fi
fi

"$SCRIPT_DIR/warp-notify.sh" "Claude Code" "$MSG"
