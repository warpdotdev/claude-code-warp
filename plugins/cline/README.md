# Warp Notifications for Cline CLI

Warp terminal integration for [Cline CLI](https://cline.bot) — the open-source AI coding agent.

## Installation

Copy the hook scripts to Cline's hooks directory:

```bash
mkdir -p ~/.cline/hooks
cp plugins/cline/hooks/*.sh ~/.cline/hooks/
chmod +x ~/.cline/hooks/*.sh
```

Cline CLI discovers global hooks from `~/.cline/hooks/` (and `~/Documents/Cline/Hooks/`), and project hooks from `.cline/hooks/`. `warp-notify.sh` is a shared helper sourced by the hooks; it must sit in the same directory.

## Hooks

| Hook File | Warp Notification | When |
|---|---|---|
| `TaskStart.sh` | `session_start` | Cline starts a new task |
| `TaskComplete.sh` | `stop` | Cline finishes a task |
| `TaskError.sh` | `stop` (with error) | Cline encounters an error |
| `PreToolUse.sh` | `permission_request` | Before a tool runs |
| `PostToolUse.sh` | `tool_complete` | After a tool finishes |
| `UserPromptSubmit.sh` | `prompt_submit` | User sends a prompt |

## Requirements

- [Warp terminal](https://warp.dev)
- [Cline CLI](https://cline.bot) v2.15+
- `jq` for JSON parsing (`brew install jq`)

## How It Works

Each hook script:
1. Checks that the Warp build supports structured notifications (`WARP_CLI_AGENT_PROTOCOL_VERSION`, `WARP_CLIENT_VERSION`) and exits silently otherwise
2. Reads Cline's hook payload from stdin (`taskId`, `workspaceRoots` and the event-specific fields)
3. Builds a structured notification payload
4. Emits it via OSC 777 escape sequence to `/dev/tty`

The payloads use the same `warp://cli-agent` protocol as the Claude Code plugin.
