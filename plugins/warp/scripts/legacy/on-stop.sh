#!/bin/bash
# Hook script for Claude Code Stop event
# Sends a Warp notification when Claude completes a task

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../transcript-tail.sh"

# Read hook input from stdin
INPUT=$(cat)

# Extract transcript path from the hook input
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# Default message
MSG="Task completed"

# Try to extract prompt and response from the transcript (JSONL format)
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Get the first user prompt. Stream records and stop at the first match,
    # so memory stays at one record however long the transcript is.
    PROMPT=$(jq -rn '
        first(inputs | select(.type == "user")) | .message.content // empty
    ' "$TRANSCRIPT_PATH" 2>/dev/null)
    
    # Get the last assistant response from a bounded tail of the transcript
    RESPONSE_FILTER='
        [.[] | select(.type == "assistant" and .message.content)] | last |
        [.message.content[] | select(.type == "text") | .text] | join(" ")
    '
    RESPONSE=$(transcript_tail "$TRANSCRIPT_PATH" "$TRANSCRIPT_TAIL_BYTES" | jq -rs "$RESPONSE_FILTER" 2>/dev/null)
    
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
