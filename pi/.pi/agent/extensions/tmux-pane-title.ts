/**
 * tmux Pane Title Extension
 *
 * Renames the current tmux pane to match the pi session name.
 * - If a name was set via /name, uses that
 * - Otherwise uses <cwd-basename>
 *
 * Uses setTimeout(0) to defer title updates so they execute after
 * pi's built-in updateTerminalTitle(), preventing the "π -" prefix
 * from appearing.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import path from "node:path";
import { execFile } from "node:child_process";

function buildSessionTitle(pi: ExtensionAPI): string {
	const sessionName = pi.getSessionName();
	if (sessionName && sessionName.trim()) {
		return `pi: ${sessionName}`;
	}
	// Fallback: cwd basename
	const cwd = path.basename(process.cwd());
	return `pi: ${cwd}`;
}

function setTmuxPaneTitle(title: string) {
	if (!process.env.TMUX || !process.env.TMUX_PANE) return;
	execFile(
		"tmux",
		["select-pane", "-t", process.env.TMUX_PANE!, "-T", title],
		(err) => {
			// Silently ignore errors (e.g., tmux not available, pane detached)
			if (err && err.code !== "ENOENT") {
				// Only log unexpected errors
			}
		},
	);
}

export default function (pi: ExtensionAPI) {
	// When session starts, set the initial titles
	pi.on("session_start", async (_event, _ctx) => {
		const title = buildSessionTitle(pi);
		setTimeout(() => setTmuxPaneTitle(title), 0);
	});

	// When agent starts working, show a spinner/indicator
	pi.on("agent_start", async (_event, _ctx) => {
		const base = buildSessionTitle(pi);
		setTimeout(() => setTmuxPaneTitle(`● ${base}`), 0);
	});

	// When agent finishes, restore clean title
	pi.on("agent_end", async (_event, _ctx) => {
		const title = buildSessionTitle(pi);
		setTimeout(() => setTmuxPaneTitle(title), 0);
	});

	// Reapply title at the start of each turn — catches /rename overrides
	pi.on("turn_start", async (_event, _ctx) => {
		const title = buildSessionTitle(pi);
		setTimeout(() => setTmuxPaneTitle(title), 0);
	});

	// Clean up on shutdown
	pi.on("session_shutdown", async (_event, ctx) => {
		if (process.env.TMUX && process.env.TMUX_PANE) {
			// Reset to cwd basename when pi exits
			execFile(
				"tmux",
				[
					"select-pane",
					"-t",
					process.env.TMUX_PANE!,
					"-T",
					path.basename(process.cwd()),
				],
				() => {},
			);
		}
		ctx.ui.setTitle("");
	});
}
