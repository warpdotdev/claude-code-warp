#!/bin/bash
# Shared helpers for scraping the Claude Code session transcript.
#
# The Stop and StopFailure hooks send the user's last prompt to Warp, which
# renders it as the notification title. A transcript's `type: "user"` entries
# are not all human prompts though: Claude Code also injects local `!` bash
# output, slash-command wrappers, background subagent completions,
# cross-session messages and system reminders as user-type entries with
# ordinary text content. Without filtering, those envelopes become the title —
# e.g. a completion toast reading `<bash-stdout>arn:aws:ecs:us-east-1:...`
# instead of what the user actually asked for.
#
# The filter only skips patterns it positively recognizes; anything else is
# passed through untouched. An odd-looking title beats a missing notification.

# Envelope tags for entries Claude Code injects on its own. These are stable
# ASCII identifiers, matched at the start of the entry's text so that a human
# prompt merely quoting a tag is left alone.
WARP_SYNTHETIC_TAGS='bash-input|bash-stdout|bash-stderr'
WARP_SYNTHETIC_TAGS="$WARP_SYNTHETIC_TAGS|command-args|command-message|command-name"
WARP_SYNTHETIC_TAGS="$WARP_SYNTHETIC_TAGS|local-command-caveat|local-command-stderr|local-command-stdout"
WARP_SYNTHETIC_TAGS="$WARP_SYNTHETIC_TAGS|persisted-output|system-reminder"
WARP_SYNTHETIC_TAGS="$WARP_SYNTHETIC_TAGS|task-id|task-notification|user-prompt-submit-hook"

# Cross-session and teammate envelopes are preceded by a framing line
# ("Another Claude session sent a message:"), so their tag is not at the start
# of the entry. The framing line is human language and may be localized, so
# anchor on the tag itself and accept it anywhere in the entry.
WARP_SYNTHETIC_TAGS_ANYWHERE='cross-session-message|teammate-message'

# Markers Claude Code injects without an XML envelope. English-only, so this is
# best effort: a localized build falls through to today's behaviour rather than
# breaking.
WARP_SYNTHETIC_PREFIXES='\[Request interrupted by user|\[SYSTEM NOTIFICATION|Stop hook feedback:'

# Prints the most recent human prompt in the transcript, or nothing when the
# transcript is unreadable or holds no human prompt.
extract_last_user_prompt() {
    local transcript_path="${1:-}"

    if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
        return 0
    fi

    jq -rs \
        --arg tags "$WARP_SYNTHETIC_TAGS" \
        --arg tags_anywhere "$WARP_SYNTHETIC_TAGS_ANYWHERE" \
        --arg prefixes "$WARP_SYNTHETIC_PREFIXES" '
        [
            .[] | select(.type == "user") |
            # Human prompts are a plain string or an array with text blocks;
            # tool results are arrays of tool_result blocks and drop out here.
            (if .message.content | type == "string" then .message.content
             elif .message.content | type == "array" then
                 ([.message.content[]? | select(.type == "text") | .text] | join(" "))
             else empty
             end) as $text |
            select(($text | length) > 0) |
            select($text | test("^\\s*<(" + $tags + ")\\b") | not) |
            select($text | test("<(" + $tags_anywhere + ")\\b") | not) |
            select($text | test("^\\s*(" + $prefixes + ")") | not) |
            $text
        ] | last // empty
    ' "$transcript_path" 2>/dev/null
}

# Prints the text of the most recent assistant message in the transcript, or
# nothing when the transcript is unreadable or holds no assistant message.
extract_last_assistant_response() {
    local transcript_path="${1:-}"

    if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
        return 0
    fi

    jq -rs '
        [.[] | select(.type == "assistant" and .message.content)] | last |
        [.message.content[] | select(.type == "text") | .text] | join(" ")
    ' "$transcript_path" 2>/dev/null
}
