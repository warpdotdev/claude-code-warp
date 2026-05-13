#!/bin/bash
# Tests for find-controlling-tty.sh
#
# The function walks up the process tree using `ps`. We override `ps` as a
# shell function so the tests don't depend on the actual process tree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
source "$SCRIPT_DIR/find-controlling-tty.sh"

PASSED=0
FAILED=0

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [[ $expected == "$actual" ]]; then
        echo "  ✓ $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ $test_name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== find-controlling-tty.sh ==="

echo ""
echo "--- Emits the parent's tty when it has one ---"
ps() {
    case "$*" in
        "-o tty= -p $PPID")  echo "ttys003" ;;
        "-o ppid= -p $PPID") echo "1" ;;
        *) command ps "$@" ;;
    esac
}
result=$(find_candidate_ttys | tr '\n' ' ' | sed 's/ $//')
assert_eq "parent tty appears as /dev/<name>" "/dev/ttys003" "$result"
unset -f ps

echo ""
echo "--- Skips ancestors with no controlling tty, keeps walking ---"
ps() {
    case "$*" in
        "-o tty= -p $PPID")    echo "??" ;;
        "-o tty= -p 77001")    echo "??" ;;
        "-o tty= -p 77002")    echo "ttys004" ;;
        "-o ppid= -p $PPID")   echo "77001" ;;
        "-o ppid= -p 77001")   echo "77002" ;;
        "-o ppid= -p 77002")   echo "1" ;;
        *) command ps "$@" ;;
    esac
}
result=$(find_candidate_ttys | tr '\n' ' ' | sed 's/ $//')
assert_eq "?? entries are skipped, real tty emitted" "/dev/ttys004" "$result"
unset -f ps

echo ""
echo "--- Emits multiple ancestors if more than one has a tty ---"
# A nested case (e.g. tmux): both inner and outer ancestors have ttys.
ps() {
    case "$*" in
        "-o tty= -p $PPID")    echo "ttys001" ;;
        "-o tty= -p 88001")    echo "ttys002" ;;
        "-o ppid= -p $PPID")   echo "88001" ;;
        "-o ppid= -p 88001")   echo "1" ;;
        *) command ps "$@" ;;
    esac
}
result=$(find_candidate_ttys | tr '\n' ' ' | sed 's/ $//')
assert_eq "both ancestor ttys are emitted in order" "/dev/ttys001 /dev/ttys002" "$result"
unset -f ps

echo ""
echo "--- Emits nothing when no ancestor has a tty ---"
ps() {
    case "$*" in
        "-o tty="*) echo "??" ;;
        "-o ppid="*) echo "1" ;;
        *) command ps "$@" ;;
    esac
}
result=$(find_candidate_ttys)
assert_eq "no output when every ancestor reports ??" "" "$result"
unset -f ps

echo ""
echo "--- Honors depth limit on unbounded process chains ---"
ps() {
    case "$*" in
        "-o tty="*) echo "??" ;;
        "-o ppid="*) echo "9999" ;;
        *) command ps "$@" ;;
    esac
}
# Should terminate (not hang) even though every ppid points to a non-init pid.
start_secs=$SECONDS
find_candidate_ttys > /dev/null
elapsed=$((SECONDS - start_secs))
if (( elapsed <= 2 )); then
    echo "  ✓ depth-limited walk terminates promptly"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ depth-limited walk took too long (${elapsed}s)"
    FAILED=$((FAILED + 1))
fi
unset -f ps

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if (( FAILED > 0 )); then
    exit 1
fi
