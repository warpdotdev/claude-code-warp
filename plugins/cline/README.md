# Warp Notifications for Cline CLI

Warp terminal integration for [Cline CLI](https://cline.bot) — the open-source AI coding agent.

## Installation

Copy the hook scripts to Cline's hooks directory:

```bash
mkdir -p ~/Documents/Cline/Hooks
cp plugins/cline/hooks/*.sh ~/Documents/Cline/Hooks/
chmod +x ~/Documents/Cline/Hooks/*.sh
```

Cline automatically discovers hooks from `~/Documents/Cline/Hooks/`.

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

Each hook script is a self-contained bash script that:
1. Checks for Warp's `WARP_CLI_AGENT_PROTOCOL_VERSION` env var (exits silently if not in Warp)
2. Reads event data from stdin as JSON
3. Builds a structured notification payload
4. Emits it via OSC 777 escape sequence to `/dev/tty`

The payloads use the same `warp://cli-agent` protocol as the Claude Code plugin.
