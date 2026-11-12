# Warp Notifications for Amp

Warp terminal integration for [Amp](https://ampcode.com) — the coding agent by Sourcegraph.

## Installation

Copy the plugin file to Amp's system plugins directory (`$XDG_CONFIG_HOME/amp/plugins/` if `XDG_CONFIG_HOME` is set):

```bash
mkdir -p ~/.config/amp/plugins
cp plugins/amp/warp-notify.ts ~/.config/amp/plugins/warp-notify.ts
```

To enable it for a single project instead, copy it to `.amp/plugins/` at the project root. Run `plugins: reload` from the command palette to load it into a running thread.

## Verify

```bash
amp plugins list
```

The list should include `warp-notify.ts` with the events `session.start`, `agent.start`, `tool.call`, `tool.result` and `agent.end`.

## Requirements

- [Warp terminal](https://warp.dev)
- [Amp CLI](https://ampcode.com)

## How It Works

Uses Amp's TypeScript plugin API (`amp.on(...)`) to hook into 5 lifecycle events and emit the same `warp://cli-agent` OSC 777 structured notifications as the Claude Code plugin.

| Amp Event | Warp Notification |
|---|---|
| `session.start` | `session_start` |
| `agent.start` | `prompt_submit` |
| `tool.call` | `permission_request` |
| `tool.result` | `tool_complete` |
| `agent.end` | `stop` |

> **Note**: Amp's plugin API is experimental. Expect breaking changes.
