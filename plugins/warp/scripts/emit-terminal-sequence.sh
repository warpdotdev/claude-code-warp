#!/bin/bash
# Emits an OSC terminal escape sequence using the best available method.
#
# Claude Code 2.1.141 added a `terminalSequence` JSON output field for hooks,
# so they can deliver OSC sequences without a controlling terminal. Older
# Claude Code doesn't know that field, and Stop hooks reject unknown fields
# ("Stop hook error: JSON validation failed"), so on older versions we must
# write to /dev/tty instead.
#
# Decision tree:
#   1. CLAUDE_CODE_VERSION known, >= 2.1.141 → emit terminalSequence JSON
#   2. CLAUDE_CODE_VERSION known, <  2.1.141 → write /dev/tty; give up if missing
#   3. CLAUDE_CODE_VERSION unknown            → try /dev/tty, fall back to JSON
#
# Usage:
#   source "$SCRIPT_DIR/emit-terminal-sequence.sh"
#   SEQ=$(printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY")
#   emit_terminal_sequence "$SEQ"
#
# When the sequence is delivered via /dev/tty (side effect), nothing is printed
# to stdout. When it must go through terminalSequence, a JSON object is printed
# to stdout — the caller should ensure this reaches the hook's stdout.
#
# On Windows Git Bash / MSYS2 a /dev/tty node exists but opening it fails with
# ENXIO when the process has no controlling terminal, so the node's presence
# says nothing about whether it is usable.

# The first Claude Code version that supports the terminalSequence output field.
TERMINAL_SEQUENCE_MIN_VERSION="2.1.141"

# Write $1 to the controlling terminal; returns 1 if there isn't a usable one.
# stderr is redirected *before* the open: in `> /dev/tty 2>/dev/null` the open
# runs while stderr is still inherited, so a failure would escape. Probing and
# writing in one step also avoids a check-then-use gap if the tty goes away.
_tty_write() {
    printf '%s' "$1" 2>/dev/null > /dev/tty
}

# Compare two dotted version strings (e.g. "2.1.141" >= "2.1.141").
# Returns 0 (true) if $1 >= $2, 1 (false) otherwise.
_version_at_least() {
    local a b av bv i
    IFS=. read -ra a <<< "$1"
    IFS=. read -ra b <<< "$2"
    for ((i = 0; i < ${#b[@]}; i++)); do
        av="${a[i]:-0}"
        bv="${b[i]:-0}"
        if ((av > bv)); then return 0; fi
        if ((av < bv)); then return 1; fi
    done
    return 0
}

# Extract a bare version number (e.g. "2.1.141") from `claude --version` output,
# which may look like "claude 2.1.141" or "2.1.141" or "Claude Code v2.1.141".
_parse_cc_version() {
    echo "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Returns 0 if the running Claude Code version supports terminalSequence.
_supports_terminal_sequence() {
    local raw="${CLAUDE_CODE_VERSION:-}"
    [ -z "$raw" ] && return 1
    local ver
    ver=$(_parse_cc_version "$raw")
    [ -z "$ver" ] && return 1
    _version_at_least "$ver" "$TERMINAL_SEQUENCE_MIN_VERSION"
}

emit_terminal_sequence() {
    local seq="$1"
    [ -z "$seq" ] && return 0

    # Without jq the JSON fallback is impossible, so stay silent rather than
    # leaking "jq: command not found" as a hook error.
    command -v jq &>/dev/null || return 0

    # Classify the running Claude Code version, if we can.
    local raw="${CLAUDE_CODE_VERSION:-}"
    local ver=""
    [ -n "$raw" ] && ver=$(_parse_cc_version "$raw")

    if [ -n "$ver" ]; then
        if _version_at_least "$ver" "$TERMINAL_SEQUENCE_MIN_VERSION"; then
            # Known new Claude Code — use the structured output field.
            MSYS2_ARG_CONV_EXCL='*' jq -nc --arg seq "$seq" '{terminalSequence: $seq}'
        else
            # Known-old Claude Code — /dev/tty is the only safe path.
            # Emitting terminalSequence here would be rejected by the Stop
            # hook validator as an unknown field.
            _tty_write "$seq" || true
        fi
        return 0
    fi

    # Unknown Claude Code version — try /dev/tty, fall back to JSON
    # as a best-effort attempt for new CC without version detection.
    if _tty_write "$seq"; then
        return 0
    fi
    MSYS2_ARG_CONV_EXCL='*' jq -nc --arg seq "$seq" '{terminalSequence: $seq}'
}
