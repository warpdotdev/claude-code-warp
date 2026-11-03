#!/bin/bash
# Hook script for Claude Code Stop event
# Sends a structured Warp notification when Claude completes a task

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Legacy fallback for old Warp versions
if ! should_use_structured; then
    [ "$TERM_PROGRAM" = "WarpTerminal" ] && exec "$SCRIPT_DIR/legacy/on-stop.sh"
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

# Read hook input from stdin
INPUT=$(cat)

# Skip if a stop hook is already active (prevents double-notification)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Extract the last user prompt and assistant response from the transcript.
# Small delay to allow Claude Code to flush the current turn to the transcript file.
# The Stop hook fires before the transcript is fully written.
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
sleep 0.3
QUERY=""
RESPONSE=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Get the last human prompt from the transcript.
    # "user" type messages include both human prompts and tool-result messages.
    # Human prompts have content that is either a plain string or an array
    # containing {type:"text"} blocks. Tool-result messages have content arrays
    # containing only {type:"tool_result"} blocks. We filter to messages that
    # have at least one "text" block (or are a plain string).
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

    # Get the last assistant response
    RESPONSE=$(jq -rs '
        [.[] | select(.type == "assistant" and .message.content)] | last |
        [.message.content[] | select(.type == "text") | .text] | join(" ")
    ' "$TRANSCRIPT_PATH" 2>/dev/null)

    # Truncate for notification display
    if [ -n "$QUERY" ] && [ ${#QUERY} -gt 200 ]; then
        QUERY="${QUERY:0:197}..."
    fi
    if [ -n "$RESPONSE" ] && [ ${#RESPONSE} -gt 200 ]; then
        RESPONSE="${RESPONSE:0:197}..."
    fi
fi

# Claude Code wakes the agent again when a background task finishes or a session cron fires,
# so a Stop with either pending is a pause rather than the end of the session. Default to 0
# so --argjson always receives a number and the notification is never dropped.
#
# Agent Teams teammates are counted apart. The Stop input lists a teammate as "running" for as
# long as it exists, including while it sits idle waiting for a message, and does not say which
# teammates are idle. A working teammate wakes the agent when it reports back, but an idle one
# never does, so counting teammates as background tasks kept a finished session "in progress"
# until every teammate was stopped. The cost is the other way round: a session that ends its turn
# while a teammate is still working is reported as done, and the teammate's report then starts a
# new turn that ends in another Stop. Entries that are not objects keep counting as background
# tasks, as they did before teammates were told apart.
BACKGROUND_TASK_COUNT=$(echo "$INPUT" | jq -r '[.background_tasks // [] | .[] | select(type != "object" or .type != "teammate")] | length' 2>/dev/null)
TEAMMATE_COUNT=$(echo "$INPUT" | jq -r '[.background_tasks // [] | .[] | objects | select(.type == "teammate")] | length' 2>/dev/null)
SESSION_CRON_COUNT=$(echo "$INPUT" | jq -r '.session_crons // [] | length' 2>/dev/null)

BODY=$(build_payload "$INPUT" "stop" \
    --arg query "$QUERY" \
    --arg response "$RESPONSE" \
    --arg transcript_path "$TRANSCRIPT_PATH" \
    --argjson background_task_count "${BACKGROUND_TASK_COUNT:-0}" \
    --argjson teammate_count "${TEAMMATE_COUNT:-0}" \
    --argjson session_cron_count "${SESSION_CRON_COUNT:-0}")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
