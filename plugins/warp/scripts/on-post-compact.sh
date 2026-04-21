#!/bin/bash
# Hook script for Claude Code PostCompact event
# Emits compact_end after context compaction completes. Lets the sidebar
# restore normal session display after showing a compacting indicator.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#postcompact

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null)

BODY=$(build_payload "$INPUT" "compact_end" \
    --arg trigger "$TRIGGER")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
