#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$PLUGIN_ROOT" <<'PY'
import json
import re
import shlex
import sys
from pathlib import Path

plugin = Path(sys.argv[1])
skills = {}
for name in ("oz-finish-task", "oz-child-agent-orchestration"):
    text = (plugin / "skills" / name / "SKILL.md").read_text()
    frontmatter, body = text.removeprefix("---\n").split("\n---\n", 1)
    assert f"name: {name}\n" in frontmatter + "\n"
    assert re.search(r"^description: \S.+", frontmatter, re.MULTILINE)
    assert text.count("```") % 2 == 0
    assert '\\"' not in body, "CLI examples must quote variables, not literal quotes"
    skills[name] = body

finish = skills["oz-finish-task"]
for requirement in (
    "You MUST use this skill before stopping",
    "even if it was purely informational or no code changed",
    "summary as a message to the parent agent's inbox",
    "do not send a separate completion message",
    "Put the full answer or actionable handoff",
    "check your unread inbox",
    "one shell argument",
    "resolve the error and retry",
    "After a successful finish, stop without repeating",
    "Waiting for input is not completion",
):
    assert requirement in finish, f"Missing completion requirement: {requirement}"

command = re.search(r"```sh\n(.+)\n```", finish).group(1)
assert shlex.split(command) == [
    "$OZ_CLI", "harness-support", "finish-task",
    "--status", "<success|failure>", "--summary", "<summary>",
]
coordination = skills["oz-child-agent-orchestration"]
for requirement in (
    "for progress updates and blockers",
    "oz-finish-task",
    "do not send a separate Complete message or substitute plain-text output",
    "Immediately run",
    "run message list",
):
    assert requirement in coordination, f"Missing orchestration requirement: {requirement}"
assert "- **Complete**:" not in coordination

manifest = next(plugin.glob(".*-plugin/plugin.json"))
marketplace = next(plugin.parents[1].glob(".*/**/marketplace.json"))
metadata = json.loads(manifest.read_text())
entry = next(
    item for item in json.loads(marketplace.read_text())["plugins"]
    if item["name"] == metadata["name"]
)
assert entry["version"] == metadata["version"], "Marketplace version must match plugin"
print(f"PASS {metadata['name']}: cloud completion contract and version consistency")
PY
