// @i-know-the-amp-plugin-api-is-wip-and-very-experimental-right-now
import type { PluginAPI } from '@ampcode/plugin'

function shouldUseStructured(): boolean {
	const proto = process.env.WARP_CLI_AGENT_PROTOCOL_VERSION
	const client = process.env.WARP_CLIENT_VERSION
	if (!proto || !client) return false

	const LAST_BROKEN_STABLE = 'v0.2026.03.25.08.24.stable_05'
	const LAST_BROKEN_PREVIEW = 'v0.2026.03.25.08.24.preview_05'

	let threshold = ''
	if (client.includes('stable')) threshold = LAST_BROKEN_STABLE
	else if (client.includes('preview')) threshold = LAST_BROKEN_PREVIEW

	if (threshold && !(client > threshold)) return false
	return true
}

function warpNotify(payload: Record<string, unknown>): void {
	if (!shouldUseStructured()) return
	const body = JSON.stringify(payload)
	try {
		const fs = require('fs')
		fs.writeFileSync('/dev/tty', `\x1b]777;notify;warp://cli-agent;${body}\x07`)
	} catch {}
}

function buildPayload(event: string, extra: Record<string, unknown> = {}): Record<string, unknown> {
	const cwd = process.cwd()
	return {
		v: 1,
		agent: 'amp',
		event,
		cwd,
		project: cwd.split('/').pop() || '',
		...extra,
	}
}

export default function (amp: PluginAPI) {
	amp.on('session.start', (event) => {
		warpNotify(buildPayload('session_start', {
			session_id: event.thread?.id || 'unknown',
		}))
	})

	amp.on('agent.start', (event) => {
		const query = event.message.length > 200 ? event.message.slice(0, 197) + '...' : event.message
		warpNotify(buildPayload('prompt_submit', {
			session_id: event.thread.id,
			query,
		}))
	})

	amp.on('tool.call', (event, ctx) => {
		const summary = `Wants to run ${event.tool}`
		warpNotify(buildPayload('permission_request', {
			session_id: event.thread.id,
			summary,
			tool_name: event.tool,
			tool_input: event.input,
		}))
		return { action: 'allow' }
	})

	amp.on('tool.result', (event) => {
		warpNotify(buildPayload('tool_complete', {
			session_id: event.thread.id,
			tool_name: event.tool,
		}))
	})

	amp.on('agent.end', (event) => {
		const query = event.message.length > 200 ? event.message.slice(0, 197) + '...' : event.message
		warpNotify(buildPayload('stop', {
			session_id: event.thread.id,
			query,
		}))
	})
}
