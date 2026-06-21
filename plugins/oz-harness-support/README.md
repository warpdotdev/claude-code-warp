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

## Requirements

- Warp's Oz cloud agent environment (provides the `oz` CLI and `OZ_*` environment variables)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- `jq` for JSON parsing
