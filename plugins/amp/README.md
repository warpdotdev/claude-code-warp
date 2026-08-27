# Warp Notifications for Amp

Warp terminal integration for [Amp](https://ampcode.com) — the coding agent by Sourcegraph.

## Installation

Copy the plugin file to Amp's global plugins directory:

```bash
cp plugins/amp/warp-notify.ts ~/.config/amp/plugins/warp-notify.ts
```

Then run Amp with plugins enabled:

```bash
PLUGINS=all amp
```

To enable permanently, add to your shell profile:

```bash
echo 'export PLUGINS=all' >> ~/.zshrc
```

## Verify

```bash
PLUGINS=all amp plugins list
```

You should see:
```
✓ /Users/you/.config/amp/plugins/warp-notify.ts active
  Events: session.start, agent.start, tool.call, tool.result, agent.end
```

## Requirements

- [Warp terminal](https://warp.dev)
- [Amp CLI](https://ampcode.com) (binary install, not npm)
- `PLUGINS=all` environment variable

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
