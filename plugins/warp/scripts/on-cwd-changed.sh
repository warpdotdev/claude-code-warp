#!/bin/bash
# Hook script for Claude Code CwdChanged event
# Emits cwd_changed so the sidebar project label reflects cd commands executed
# by Claude. The envelope's `project` field is derived from basename(cwd) at
# notification time — this event pushes the update without waiting for the
# next tool call.
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#cwdchanged

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

# No extra fields — the envelope already carries the new cwd and derived project.
BODY=$(build_payload "$INPUT" "cwd_changed")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
