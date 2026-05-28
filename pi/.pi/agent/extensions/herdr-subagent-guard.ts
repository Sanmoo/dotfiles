// Prevent headless pi-subagents from reporting/releasing the parent Herdr pane.
// Load this before Herdr's own integration via ~/.pi/agent/settings.json `extensions`.
// Subagent child processes are marked by pi-subagents with PI_SUBAGENT_CHILD=1.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

if (process.env.PI_SUBAGENT_CHILD === "1") {
	process.env.HERDR_ENV = "0";
	delete process.env.HERDR_PANE_ID;
	delete process.env.HERDR_SOCKET_PATH;
}

export default function (_pi: ExtensionAPI) {}
