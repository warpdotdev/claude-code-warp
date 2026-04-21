#!/bin/bash
# Hook script for Claude Code SessionStart event
# Emits session_start with plugin version, Claude Code model, permission mode,
# and the source that triggered the start (startup, resume, clear, compact).
#
# https://docs.anthropic.com/en/docs/claude-code/hooks#sessionstart-input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Legacy fallback for old Warp versions
if ! should_use_structured; then
    exec "$SCRIPT_DIR/legacy/on-session-start.sh"
fi

if ! command -v jq &>/dev/null; then
    cat << 'EOF'
{
  "systemMessage": "🚨 Warp notifications require jq! Install it with your system package manager (e.g. brew install jq, apt install jq) 🚨"
}
EOF
    exit 0
fi
source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

PLUGIN_VERSION=$(jq -r '.version // "unknown"' "$SCRIPT_DIR/../.claude-plugin/plugin.json" 2>/dev/null)

# SessionStart-specific context — lets Warp disambiguate fresh sessions from
# resumed/cleared/compacted ones, and surface the active model in the sidebar.
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"' 2>/dev/null)
MODEL=$(echo "$INPUT" | jq -r '.model // empty' 2>/dev/null)
PERMISSION_MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)

# Clear any leftover per-session temp files from a previous run that ended abruptly.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
    rm -f "${TMPDIR:-/tmp}/warp-claude-${SESSION_ID}".* 2>/dev/null || true
fi

BODY=$(build_payload "$INPUT" "session_start" \
    --arg plugin_version "$PLUGIN_VERSION" \
    --arg source "$SOURCE" \
    --arg model "$MODEL" \
    --arg permission_mode "$PERMISSION_MODE" \
    --arg agent_type "$AGENT_TYPE")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
