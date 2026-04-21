# Claude Code + Warp

Official [Warp](https://warp.dev) terminal integration for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## Features

### 🔔 Native Notifications

Get native Warp notifications when Claude Code:
- **Completes a task** — with a summary showing your prompt and Claude's response
- **Completes a subagent** — when a nested Agent tool call finishes, with the subagent's response
- **Needs your input** — when Claude has been idle and is waiting for you
- **Requests permission** — when Claude wants to run a tool and needs your approval
- **Is auto-denied** — when the auto-mode classifier silently denies a tool call
- **Hits an API error** — rate limits, auth failures, billing errors surface in the sidebar instead of silently hanging
- **Asks a question via MCP** — MCP elicitation dialogs are routed through the same `question_asked` event OpenCode uses

Notifications appear in Warp's notification center and as system notifications, so you can context-switch while Claude works and get alerted when attention is needed.

### 📡 Session Status

The plugin keeps Warp's sidebar in sync with Claude's lifecycle by emitting structured events on every transition:

- **Session start / end** — appear and disappear from the sidebar cleanly (`clear`, `resume`, `logout` reasons included)
- **Prompt submitted** — you sent a prompt, Claude is working
- **Permission request / denied** — awaiting approval, or silently denied by auto mode
- **Tool complete / failed** — distinguishes successful tool calls from errors
- **Subagent start / stop** — nested Agent runs visible in the sidebar instead of looking like one opaque tool call
- **Compact start / end** — context compaction is surfaced rather than appearing as a frozen session
- **Cwd changed** — sidebar project label updates in real time when Claude runs `cd`

Every event includes rich context: `permission_mode`, `model`, `source`, and event-specific payloads (tool previews, error types, subagent types) so Warp can render state with high fidelity.

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
- `jq` for JSON parsing (install via `brew install jq` or your package manager)

## How It Works

The plugin communicates with Warp via OSC 777 escape sequences. Each hook script builds a structured JSON payload (via `build-payload.sh`) and sends it to `warp://cli-agent`, where Warp parses it to drive notifications and session UI.

Payloads include a protocol version negotiated between the plugin and Warp (`min(plugin_version, warp_version)`), the session ID, working directory, and event-specific fields. Every handler has a 5-second timeout; `Stop`, `StopFailure`, and `SubagentStop` run async so the session response isn't blocked on tty writes.

### Hook inventory

The plugin registers sixteen hooks covering the full [Claude Code hook lifecycle](https://docs.anthropic.com/en/docs/claude-code/hooks):

| Claude Code hook | Warp event | Sidebar effect |
|---|---|---|
| `SessionStart` (`startup\|resume\|clear\|compact`) | `session_start` | registers/refreshes the sidebar entry; `model` + `source` surface in the UI |
| `SessionEnd` | `session_end` | archives the sidebar entry with termination reason |
| `UserPromptSubmit` | `prompt_submit` | transitions tab idle/done → running |
| `PermissionRequest` | `permission_request` | transitions tab → blocked-awaiting-permission with a rich summary |
| `PermissionDenied` | `permission_denied` | clears the blocked state when auto-mode classifier denies |
| `PostToolUse` (matcher: `Bash\|Edit\|Write\|MultiEdit\|NotebookEdit\|Agent`) | `tool_complete` | transitions tab → running with tool preview |
| `PostToolUseFailure` | `tool_failed` | distinguishes failed tool calls from successful ones |
| `SubagentStart` | `subagent_start` | surfaces nested Agent runs instead of flat "running" state |
| `SubagentStop` | `subagent_stop` | subagent's final response appears in the sidebar |
| `Notification` (`idle_prompt`) | `idle_prompt` | "waiting for input" badge |
| `Stop` | `stop` | transitions tab → done with prompt/response summary |
| `StopFailure` | `stop` (with `error` field) | API errors (rate limits, auth) surface instead of hanging |
| `PreCompact` / `PostCompact` | `compact_start` / `compact_end` | sidebar shows compaction instead of looking frozen |
| `CwdChanged` | `cwd_changed` | project label updates in real time on `cd` |
| `Elicitation` | `question_asked` | MCP elicitation routes through the existing OpenCode-compatible event |

### Payload envelope

Every payload carries the six-field common envelope:

```json
{
  "v": 1,
  "agent": "claude",
  "event": "<event>",
  "session_id": "<session-id>",
  "cwd": "<absolute-path>",
  "project": "<basename-of-cwd>"
}
```

Plus event-specific fields. Many events also include `permission_mode` (plan / acceptEdits / auto / bypassPermissions / default) so Warp can adapt sidebar rendering to the current mode. `SessionStart` additionally includes `model` and `source`.

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

Plugin v2.0.1 adds new Warp events (`session_end`, `permission_denied`, `tool_failed`, `subagent_start`, `subagent_stop`, `compact_start`, `compact_end`, `cwd_changed`) on top of v2.0.0's six-event baseline. Warp clients that don't know these events should silently ignore them; newer clients render them as first-class sidebar states. All existing v2.0.0 events are emitted unchanged — this is a backward-compatible patch.

## License

MIT License — see [LICENSE](LICENSE) for details.
