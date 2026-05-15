/**
 * Agent Done Notify Extension
 *
 * Sends a desktop notification via `notify-send` when the agent finishes
 * processing a prompt and is waiting for input. The `/notify` command
 * toggles notifications on/off. State is persisted across sessions.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import path from "node:path";
import { execFile } from "node:child_process";

const STORAGE_KEY = "agent-done-notify";

export default function (pi: ExtensionAPI) {
	let enabled = true;

	// Restore persisted state on session start
	pi.on("session_start", (_event, ctx) => {
		for (const entry of ctx.sessionManager.getEntries()) {
			if (entry.type === "custom" && entry.customType === STORAGE_KEY) {
				const data = entry.data;
				if (data && typeof data === "object" && "enabled" in data) {
					enabled = Boolean((data as Record<string, unknown>).enabled);
				}
				break;
			}
		}
	});

	function notifyUser() {
		if (!enabled) return;

		const session = pi.getSessionName();
		const label =
			session && session.trim() ? session : path.basename(process.cwd());

		// Play notification sound via PipeWire (freedesktop sound theme)
		execFile(
			"pw-play",
			["/usr/share/sounds/freedesktop/stereo/complete.oga"],
			(err) => {
				if (!err) return;
				if (err.code === "ENOENT") {
					// pw-play not available — skip sound silently
				}
			},
		);

		execFile(
			"notify-send",
			["Pi", `Ready for input \u2014 ${label}`],
			(err) => {
				if (!err) return;
				if (err.code === "ENOENT") {
					// notify-send not installed — fail silently
					return;
				}
				console.warn("notify-send failed (non-fatal):", err.message);
			},
		);
	}

	// Fire notification when agent finishes
	pi.on("agent_end", () => {
		notifyUser();
	});

	// Fire notification when agent asks a question (waiting for user input)
	pi.on("tool_call", (event) => {
		if (event.toolName === "ask_user_question") {
			notifyUser();
		}
	});

	// /notify command to control notifications
	pi.registerCommand("notify", {
		description:
			"Control desktop notifications when agent finishes. Usage: /notify [on|off|toggle]",
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase();

			if (!arg || arg === "status") {
				ctx.ui.notify(`Notifications: ${enabled ? "on" : "off"}`, "info");
				return;
			}

			if (arg === "on") {
				enabled = true;
				pi.appendEntry(STORAGE_KEY, { enabled: true });
				ctx.ui.notify("Notifications enabled", "success");
			} else if (arg === "off") {
				enabled = false;
				pi.appendEntry(STORAGE_KEY, { enabled: false });
				ctx.ui.notify("Notifications disabled", "warning");
			} else if (arg === "toggle") {
				enabled = !enabled;
				pi.appendEntry(STORAGE_KEY, { enabled });
				ctx.ui.notify(
					`Notifications ${enabled ? "enabled" : "disabled"}`,
					enabled ? "success" : "warning",
				);
			} else {
				ctx.ui.notify("Usage: /notify [on|off|toggle]", "error");
			}
		},
	});
}
