#!/bin/bash
#
# Smoke test for the mirrored factory-files skill.
#
# The skill tree under skills/factory-files is a byte-for-byte copy of
# resources/bundled/skills/factory-files in warpdotdev/warp at the commit named
# in this plugin's README. Its own regression corpus lives there; this checks
# the one thing the copy can get wrong on its way over, which is arriving
# incomplete or unrunnable.
#
# The validator prefers warp-server and falls back to the bundled schemas, so
# every run here passes --offline: CI has no server and no API key, and the
# offline floor is what a mirror needs to guarantee.

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
    "$SKILL/schemas/common.schema.json" \
    "$SKILL/schemas/factory.schema.json" \
    "$SKILL/schemas/agent.schema.json" \
    "$SKILL/schemas/automation.schema.json" \
    "$SKILL/schemas/runner.schema.json" \
    "$SKILL/schemas/scorer.schema.json" \
    "$SKILL/references/examples.md" \
    "$SKILL/references/scorers.md" \
    "$SKILL/references/validation.md"; do
    if [ -f "$required" ]; then
        pass "present: ${required#"$SKILL/"}"
    else
        fail "missing: ${required#"$SKILL/"}"
    fi
done

if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required to run the bundled validator"
    echo "  $PASSED passed, $FAILED failed"
    exit 1
fi

WORKSPACE="$(mktemp -d)"
trap 'rm -rf "$WORKSPACE"' EXIT

mkdir -p "$WORKSPACE/valid/agents/main" "$WORKSPACE/invalid/agents/main"
cat >"$WORKSPACE/valid/factory.yaml" <<'YAML'
schemaVersion: v1alpha1
name: mirror-smoke
repositories:
  - owner: warpdotdev
    name: warp
agentDefaults:
  model: auto
YAML
printf -- '---\nagentType: MAIN\n---\nDo the thing.\n' >"$WORKSPACE/valid/agents/main/agent.md"

# The same tree with no MAIN agent, which the tree-level rules must reject.
cp "$WORKSPACE/valid/factory.yaml" "$WORKSPACE/invalid/factory.yaml"
printf -- '---\ndescription: no main agent\n---\nDo the thing.\n' >"$WORKSPACE/invalid/agents/main/agent.md"

output="$(python3 "$VALIDATOR" "$WORKSPACE/valid" --offline 2>&1)"
if [ $? -eq 0 ]; then
    pass "a valid tree is accepted offline"
else
    fail "a valid tree was rejected offline" "$output"
fi

case "$output" in
    *"Server validation was unavailable"*)
        pass "the offline fallback is disclosed"
        ;;
    *)
        fail "the offline fallback was not disclosed" "$output"
        ;;
esac

output="$(python3 "$VALIDATOR" "$WORKSPACE/invalid" --offline 2>&1)"
if [ $? -ne 0 ]; then
    pass "a tree with no MAIN agent is rejected offline"
else
    fail "a tree with no MAIN agent was accepted offline" "$output"
fi

echo "  $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
