#!/bin/bash
# Windows-only notification sender with deduplication
# Usage: win-notify.sh <event_type> <json_input>
#
# Only one notification per 8 seconds to prevent duplicates from
# multiple hooks firing on the same Claude Code event.

# Only run on Windows
[ -z "$WINDIR" ] && exit 0
command -v powershell &>/dev/null || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EVENT_TYPE="${1:-unknown}"
INPUT="${2:-{}}"

# === Deduplication ===
LOCK_DIR="/tmp/warp-notify-lock"
if mkdir "$LOCK_DIR" 2>/dev/null; then
    # We got the lock — we're the first hook to fire
    # Clean up lock after 8 seconds (background)
    (sleep 8 && rmdir "$LOCK_DIR" 2>/dev/null) &
else
    # Another hook already fired recently — skip
    exit 0
fi

# === Extract context ===
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
PROJECT=""
if [ -n "$CWD" ]; then
    PROJECT=$(basename "$CWD")
fi

# === Build notification title and body based on event type ===
case "$EVENT_TYPE" in
    stop)
        NOTIF_TITLE="✅ Task Completed"
        # Try to get the response summary
        TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
        RESPONSE=""
        QUERY=""
        if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
            RESPONSE=$(jq -rs '
                [.[] | select(.type == "assistant" and .message.content)] | last |
                [.message.content[] | select(.type == "text") | .text] | join(" ")
            ' "$TRANSCRIPT_PATH" 2>/dev/null)
            QUERY=$(jq -rs '
                [
                    .[] | select(.type == "user") |
                    if .message.content | type == "string" then .
                    elif [.message.content[] | select(.type == "text")] | length > 0 then .
                    else empty end
                ] | last |
                if .message.content | type == "array"
                then [.message.content[] | select(.type == "text") | .text] | join(" ")
                else .message.content // empty end
            ' "$TRANSCRIPT_PATH" 2>/dev/null)
        fi
        if [ -n "$RESPONSE" ]; then
            NOTIF_BODY="${RESPONSE:0:200}"
        elif [ -n "$QUERY" ]; then
            NOTIF_BODY="Done: ${QUERY:0:200}"
        else
            NOTIF_BODY="Claude finished the task"
        fi
        ;;
    idle_prompt)
        NOTIF_TITLE="⏳ Input Needed"
        MSG=$(echo "$INPUT" | jq -r '.message // empty' 2>/dev/null)
        NOTIF_BODY="${MSG:-Claude is waiting for your input}"
        ;;
    permission_request)
        NOTIF_TITLE="🔐 Permission Required"
        TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "a tool"' 2>/dev/null)
        NOTIF_BODY="Claude wants to run: $TOOL_NAME"
        ;;
    session_start)
        # Don't notify on session start — not useful
        rmdir "$LOCK_DIR" 2>/dev/null
        exit 0
        ;;
    *)
        NOTIF_TITLE="Claude Code"
        NOTIF_BODY="Needs your attention"
        ;;
esac

# === Add project context ===
if [ -n "$PROJECT" ]; then
    NOTIF_TITLE="$NOTIF_TITLE — $PROJECT"
fi

# === Fire Windows notification ===
powershell -ExecutionPolicy Bypass -NoProfile -File "$SCRIPT_DIR/win-toast.ps1" \
    -Title "$NOTIF_TITLE" -Body "$NOTIF_BODY" &>/dev/null &
