#!/bin/bash
# Reads only the end of a Claude Code transcript.
#
# Transcripts grow for the whole session and can reach gigabytes. Slurping the
# whole file with `jq -s` costs about three times its size in memory at every
# turn end, while the last prompt and response sit within the final few
# hundred KB. Reading a bounded tail keeps the Stop hook's memory flat.
#
# Usage:
#   source "$SCRIPT_DIR/transcript-tail.sh"
#   transcript_tail "$TRANSCRIPT_PATH" "$TRANSCRIPT_TAIL_BYTES" | jq -rs '...'

# Window to read, and the larger one to retry with when the last prompt
# is further back (a long autonomous turn with big tool results).
TRANSCRIPT_TAIL_BYTES=4194304
TRANSCRIPT_TAIL_MAX_BYTES=33554432

# Prints the last $2 bytes of transcript $1, dropping the partial line the cut
# lands in. Transcripts are JSONL, so every remaining line is a whole record.
transcript_tail() {
    local path="$1" bytes="$2"
    if [ "$(wc -c < "$path")" -gt "$bytes" ]; then
        tail -c "$bytes" "$path" | tail -n +2
    else
        cat "$path"
    fi
}

# Returns 0 if transcript $1 is larger than $2 bytes, so a bigger window could
# find something the smaller one missed.
transcript_larger_than() {
    [ "$(wc -c < "$1")" -gt "$2" ]
}
