// Make Herdr's Pi integration aware of pi-subagents.
//
// 1. In child subagents, disable inherited HERDR_* pane identity so a headless
//    child cannot report/release the parent pane.
// 2. In the parent session, report the Herdr pane as `working` while any async
//    subagent is still running. This avoids false `done` notifications after
//    the parent Pi finishes the turn that launched the async work.

import { createConnection } from "node:net";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const isSubagentChild = process.env.PI_SUBAGENT_CHILD === "1";
const HERDR_ENV = process.env.HERDR_ENV;
const socketPath = process.env.HERDR_SOCKET_PATH;
const paneId = process.env.HERDR_PANE_ID;
const source = "herdr:pi-subagents-guard";

if (isSubagentChild) {
	process.env.HERDR_ENV = "0";
	delete process.env.HERDR_PANE_ID;
	delete process.env.HERDR_SOCKET_PATH;
}

function herdrEnabled() {
	return HERDR_ENV === "1" && !!socketPath && !!paneId;
}

function sendRequest(request: unknown): Promise<void> {
	if (!herdrEnabled()) return Promise.resolve();

	return new Promise((resolve) => {
		let done = false;
		let timeout: ReturnType<typeof setTimeout> | undefined;
		const socket = createConnection(socketPath!);

		const finish = () => {
			if (done) return;
			done = true;
			if (timeout) clearTimeout(timeout);
			socket.destroy();
			resolve();
		};

		socket.on("error", finish);
		socket.on("connect", () => socket.write(`${JSON.stringify(request)}\n`));
		socket.on("data", finish);
		socket.on("end", finish);
		timeout = setTimeout(finish, 500);
		timeout.unref?.();
	});
}

function reportHerdrState(state: "working" | "idle", message?: string) {
	void sendRequest({
		id: `${source}:${Date.now()}:${Math.random().toString(36).slice(2)}`,
		method: "pane.report_agent",
		params: {
			pane_id: paneId,
			source,
			agent: "pi",
			state,
			message,
			seq: Date.now() * 1000,
		},
	});
}

export default function (pi: ExtensionAPI) {
	if (isSubagentChild) return;

	const activeAsyncRuns = new Set<string>();
	let parentAgentActive = false;

	function runId(data: unknown): string {
		const value =
			(data as { id?: unknown; runId?: unknown })?.id ??
			(data as { runId?: unknown })?.runId;
		return typeof value === "string" && value.length > 0
			? value
			: `unknown-${Date.now()}`;
	}

	function publishAsyncState() {
		if (activeAsyncRuns.size > 0) {
			reportHerdrState("working", "pi-subagents running");
			return;
		}
		if (!parentAgentActive) reportHerdrState("idle");
	}

	pi.on("agent_start", () => {
		parentAgentActive = true;
	});

	pi.on("agent_end", () => {
		parentAgentActive = false;
		// Herdr's official integration schedules idle shortly after agent_end.
		// Reassert working after that debounce when async subagents are still active.
		setTimeout(publishAsyncState, 300).unref?.();
	});

	pi.events.on("subagent:async-started", (data) => {
		activeAsyncRuns.add(runId(data));
		publishAsyncState();
	});

	pi.events.on("subagent:async-complete", (data) => {
		activeAsyncRuns.delete(runId(data));
		publishAsyncState();
	});

	pi.on("session_shutdown", () => {
		activeAsyncRuns.clear();
		publishAsyncState();
	});
}
