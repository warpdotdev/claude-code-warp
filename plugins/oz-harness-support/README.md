# oz-harness-support

Warp integration for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) running inside Warp's **Oz cloud agent** environments.

This plugin is installed automatically in Oz cloud agent environments — there is no manual setup for end users.

## Hooks

The plugin registers an Oz parent-message delivery bridge:
- **SessionStart** — starts the parent-message listener for the run
- **UserPromptSubmit** / **PostToolUse** — drain the mailbox, surfacing queued parent messages into the session as additional context
- **Stop** — keeps the session active when parent messages are still pending delivery
- **SessionEnd** — tears down the listener and cleans up hook state

## Skills

The plugin ships skills the agent uses to talk to the Oz platform:
- **oz-child-agent-orchestration** — coordinate with a lead run via the Oz CLI (`OZ_CLI`, `OZ_RUN_ID`, `OZ_PARENT_RUN_ID`)
- **oz-finish-task** — report task completion or failure
- **oz-notify-user** — send a progress notification to the triggering user
- **oz-report-pr** — report a created pull request back to Oz
- **oz-upload-file** — upload a local file as a conversation artifact
- **factory-files** — author and validate file-based Warp software factory definitions

### factory-files is a mirror

`skills/factory-files` is a byte-for-byte copy of
`resources/bundled/skills/factory-files` in
[warpdotdev/warp](https://github.com/warpdotdev/warp), mirrored at commit
`f6f4ceac8`. Warp bundles that skill for its own clients; Claude Code loads
filesystem skills from this plugin instead, so it is copied here rather than
resolved from a bundle. Change it in `warpdotdev/warp` and re-mirror; edits
made here are lost on the next sync.

The skill validates only against warp-server, which owns the Factory file
format. It carries no copy of that format: a bundled copy ships inside a
release, goes stale, and then reports valid fields as unknown, which invites an
agent to delete working configuration. When the server cannot be reached the
skill reports that the tree was not checked rather than guessing.

That also keeps this mirror cheap. There is no schema here to drift, so a stale
copy costs a stale workflow document, not a wrong verdict.
`tests/test-factory-files.sh` checks the copy arrived complete, carries no
schemas, and reports a missing verdict correctly; its behavioural corpus lives
in Warp.

## Requirements

- Warp's Oz cloud agent environment (provides the `oz` CLI and `OZ_*` environment variables)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- `jq` for JSON parsing
