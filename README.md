# Claude Code + Warp

Official [Warp](https://warp.dev) terminal integration for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## Features

### 🔔 Native Notifications

Get native Warp notifications when Claude Code:
- **Completes a task** — with a summary showing your prompt and Claude's response
- **Needs your input** — when Claude has been idle and is waiting for you
- **Requests permission** — when Claude wants to run a tool and needs your approval

Notifications appear in Warp's notification center and as system notifications, so you can context-switch while Claude works and get alerted when attention is needed.

### 📡 Session Status

The plugin keeps Warp informed of Claude's current state by emitting structured events on every session transition:
- **Prompt submitted** — you sent a prompt, Claude is working
- **Tool completed** — a tool call finished, Claude is back to running

This powers Warp's inline status indicators for Claude Code sessions.

## Installation

```bash
# In Claude Code, add the marketplace
/plugin marketplace add warpdotdev/claude-code-warp

# Install the Warp plugin
/plugin install warp@claude-code-warp
```

> ⚠️ **Important**: After installing, **restart Claude Code or run /reload-plugins** for the plugin to activate.

Once restarted, you'll see a confirmation message and notifications will appear automatically.

## Requirements

- [Warp terminal](https://warp.dev) (macOS, Linux, or Windows)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- `jq` for JSON parsing — install via your package manager:
  - macOS: `brew install jq`
  - Linux: `sudo apt install jq` (Debian/Ubuntu) or `sudo dnf install jq` (Fedora)
  - Windows: `scoop install jq` or `choco install jq`

## How It Works

The plugin communicates with Warp via OSC 777 escape sequences. Each hook script builds a structured JSON payload (via `build-payload.sh`) and sends it to `warp://cli-agent`, where Warp parses it to drive notifications and session UI.

Payloads include a protocol version negotiated between the plugin and Warp (`min(plugin_version, warp_version)`), the session ID, working directory, and event-specific fields.

The plugin registers six hooks:
- **SessionStart** — emits the plugin version and a welcome system message
- **Stop** — reads the transcript to extract your prompt and Claude's response, then sends a task-complete notification
- **Notification** (`idle_prompt`) — fires when Claude has been idle and needs your input
- **PermissionRequest** — fires when Claude wants to run a tool, includes the tool name and a preview of its input
- **UserPromptSubmit** — fires when you submit a prompt, signaling the session is active again
- **PostToolUse** — fires when a tool call completes, signaling the session is no longer blocked

### Legacy Support

Older Warp clients that predate the structured notification protocol are still supported — they receive plain-text notifications for SessionStart, Stop, and Notification hooks.


## Configuration

Notifications work out of the box. To customize Warp's notification behavior (sounds, system notifications, etc.), see [Warp's notification settings](https://docs.warp.dev/features/notifications).

## Uninstall

```bash
/plugin uninstall warp@claude-code-warp
/plugin marketplace remove claude-code-warp
```

## Versioning

The plugin version in `plugins/warp/.claude-plugin/plugin.json` is checked by the Warp client to detect outdated installations.
When bumping the version here, also update `MINIMUM_PLUGIN_VERSION` in the Warp client.

## Oz Cloud Agent Support

Running Claude Code inside Warp's Oz cloud agents? See the [`oz-harness-support` plugin](plugins/oz-harness-support/README.md), installed automatically in those environments.

## License

MIT License — see [LICENSE](LICENSE) for details.
