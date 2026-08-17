#!/bin/bash
#
# Smoke test for the mirrored factory-files skill.
#
# The skill tree under skills/factory-files is a byte-for-byte copy of
# resources/bundled/skills/factory-files in warpdotdev/warp at the commit named
# in this plugin's README. Correctness of the Factory file format is owned by
# warp-server, and the skill's own behavioural corpus lives in warp; this
# checks the two things a copy can get wrong on its way over: arriving
# incomplete, and arriving with a local copy of the format that should not
# exist.
#
# There is no offline mode to exercise. CI has no warp-server, so the runnable
# assertion here is that the validator reports a tree as NOT validated rather
# than guessing at a verdict.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$PLUGIN_ROOT/skills/factory-files"
VALIDATOR="$SKILL/scripts/validate_factory_files.py"

PASSED=0
FAILED=0

pass() {
    echo "  ✓ $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "  ✗ $1"
    [ -n "${2:-}" ] && echo "    $2"
    FAILED=$((FAILED + 1))
}

echo "factory-files mirror"

for required in \
    "$SKILL/SKILL.md" \
    "$VALIDATOR" \
    "$SKILL/references/examples.md" \
    "$SKILL/references/scorers.md" \
    "$SKILL/references/validation.md"; do
    if [ -f "$required" ]; then
        pass "present: ${required#"$SKILL/"}"
    else
        fail "missing: ${required#"$SKILL/"}"
    fi
done

# A bundled copy of the format is the failure this design removed: it ships
# inside a release, goes stale against the server, and then reports valid
# fields as unknown.
if find "$SKILL" -name '*.schema.json' | grep -q .; then
    fail "the mirror carries bundled schemas, which go stale against the server"
else
    pass "no local copy of the format"
fi

if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required to run the validator"
    echo "  $PASSED passed, $FAILED failed"
    exit 1
fi

if python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$VALIDATOR" 2>/dev/null; then
    pass "the validator parses"
else
    fail "the validator does not parse"
fi

WORKSPACE="$(mktemp -d)"
trap 'rm -rf "$WORKSPACE"' EXIT

mkdir -p "$WORKSPACE/tree/agents/main"
cat >"$WORKSPACE/tree/factory.yaml" <<'YAML'
schemaVersion: v1alpha1
name: mirror-smoke
repositories:
  - owner: warpdotdev
    name: warp
agentDefaults:
  model: auto
YAML
printf -- '---\nagentType: MAIN\n---\nDo the thing.\n' >"$WORKSPACE/tree/agents/main/agent.md"

# Port 9 (discard) is reliably closed, so this exercises the unreachable-server
# path without depending on the network.
output="$(python3 "$VALIDATOR" "$WORKSPACE/tree" --server-root http://127.0.0.1:9 2>&1)"
status=$?
if [ "$status" -eq 2 ]; then
    pass "an unreachable server exits 2"
else
    fail "an unreachable server should exit 2, got $status" "$output"
fi

case "$output" in
    *"was NOT validated"*)
        pass "an unreachable server is reported as not validated"
        ;;
    *)
        fail "the missing verdict was not reported" "$output"
        ;;
esac

case "$output" in
    *"Validated with the warp-server parser"*)
        fail "a run with no server claimed a server verdict" "$output"
        ;;
    *)
        pass "no verdict is claimed without a server"
        ;;
esac

echo "  $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
