#!/bin/bash
# Extracts the last human-authored prompt from a Claude Code transcript.
#
# Usage: source this file, then call extract_query with the transcript path.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/extract-query.sh"
#   QUERY=$(extract_query "$TRANSCRIPT_PATH")
#
# Not every "user" entry in the transcript is something a human typed. Claude
# Code injects turns of its own — background task notifications, skill loads,
# slash-command expansions, compaction summaries — and stores them with
# type "user" too. Those carry an origin.kind other than "human" (or no origin
# at all, plus isMeta: true), and their content is raw markup like
# <task-notification>. Selecting purely on type "user" surfaces that markup in
# the notification, so we key on origin.kind instead.

# jq program: prefer the last origin.kind == "human" message; if the transcript
# predates the origin field, fall back to the last non-meta message whose text
# doesn't start with an injected-markup tag.
EXTRACT_QUERY_JQ='
    [
        .[]
        | select(.type == "user" and .isMeta != true)
        | {
            origin: .origin.kind,
            text: (
                if .message.content | type == "string" then .message.content
                else [.message.content[]? | select(.type == "text") | .text] | join(" ")
                end
            )
          }
        | select(.text != null and .text != "")
    ] as $msgs
    | (
        ([$msgs[] | select(.origin == "human")] | last)
        // ([$msgs[] | select(.origin == null and (.text | test("^[[:space:]]*<[a-zA-Z-]+>") | not))] | last)
      )
    | .text // empty
'

extract_query() {
    local transcript_path="$1"
    [ -n "$transcript_path" ] && [ -f "$transcript_path" ] || return 0
    jq -rs "$EXTRACT_QUERY_JQ" "$transcript_path" 2>/dev/null
}
