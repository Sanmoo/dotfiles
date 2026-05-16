/**
 * Session Model Isolation Extension
 *
 * Prevents model/thinking changes from persisting to settings.json.
 * Captures a snapshot of the current model/thinking settings at session start
 * and restores them after every tool call, preventing accidental persistence
 * of temporary session changes.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	existsSync,
	mkdirSync,
	readFileSync,
	unlinkSync,
	writeFileSync,
} from "node:fs";
import { dirname, resolve } from "node:path";
import { homedir } from "node:os";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Walk up from `cwd` looking for a directory containing `.pi/`.
 * Returns the project root (the parent of `.pi/`) or null if not found.
 */
export function findProjectRoot(cwd: string): string | null {
	let current = resolve(cwd);
	let prev = "";
	while (current !== prev) {
		if (existsSync(resolve(current, ".pi"))) {
			return current;
		}
		prev = current;
		const next = dirname(current);
		if (next === current) break; // reached filesystem root
		current = next;
	}
	return null;
}

/**
 * Resolve the most appropriate settings file path for the session.
 *
 * Priority:
 *  1. project `.pi/settings.json`
 *  2. project `.pi/agent/settings.json`
 *  3. global `~/.pi/agent/settings.json`
 *
 * Returns null if none of these files exist.
 */
export function resolveSettingsPath(cwd: string): string | null {
	const root = findProjectRoot(cwd);

	if (root) {
		const projectSettings = resolve(root, ".pi", "settings.json");
		if (existsSync(projectSettings)) return projectSettings;

		const agentSettings = resolve(root, ".pi", "agent", "settings.json");
		if (existsSync(agentSettings)) return agentSettings;
	}

	const globalSettings = resolve(homedir(), ".pi", "agent", "settings.json");
	if (existsSync(globalSettings)) return globalSettings;

	return null;
}

/**
 * Shape of the three model/thinking fields we care about.
 */

const SETTINGS_KEYS = [
	"defaultModel",
	"defaultProvider",
	"defaultThinkingLevel",
] as const;
type SettingsKey = (typeof SETTINGS_KEYS)[number];

export type SettingsSnapshot = {
	[K in SettingsKey]?: string;
};

/**
 * Read and parse a JSON settings file.
 */
export function readSettings(path: string): Record<string, unknown> {
	let parsed: unknown;
	try {
		const raw = readFileSync(path, "utf-8");
		parsed = JSON.parse(raw);
	} catch (e) {
		throw new Error(
			`Failed to parse settings file ${path}: ${(e as Error).message}`,
		);
	}
	if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
		throw new Error(`Settings file ${path} must contain a JSON object`);
	}
	return parsed as Record<string, unknown>;
}

/**
 * Write settings object to a JSON file, creating parent directories if needed.
 */
export function writeSettings(
	path: string,
	settings: Record<string, unknown>,
): void {
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, JSON.stringify(settings, null, 2) + "\n", "utf-8");
}

/**
 * Extract the three model/thinking fields from a full settings object.
 */
export function snapshotSettings(
	settings: Record<string, unknown>,
): SettingsSnapshot {
	const result: Record<string, string | undefined> = {};
	for (const key of SETTINGS_KEYS) {
		result[key] = (settings[key] as string | undefined) ?? undefined;
	}
	return result as unknown as SettingsSnapshot;
}

/**
 * Restore the saved snapshot fields into the settings file.
 *
 * Reads the current file content, overwrites (or removes) the three fields
 * if they differ from the snapshot, and writes back only when changed.
 * If a field is `undefined` in the snapshot but present in the file, it is
 * deleted from the persisted settings.
 */
export function restoreSettings(
	filePath: string,
	snapshot: SettingsSnapshot,
	keys?: readonly SettingsKey[],
): void {
	if (!existsSync(filePath)) return;

	const current = readSettings(filePath);
	let changed = false;

	const keysToRestore = keys ?? SETTINGS_KEYS;
	for (const key of keysToRestore) {
		const snapVal = snapshot[key];
		if (snapVal === undefined) {
			// Field not in snapshot -> remove from file if present
			if (key in current) {
				delete current[key];
				changed = true;
			}
		} else {
			// Field present in snapshot -> restore if different
			if (current[key] !== snapVal) {
				current[key] = snapVal;
				changed = true;
			}
		}
	}

	if (changed) {
		writeSettings(filePath, current);
	}
}

// ---------------------------------------------------------------------------
// Extension entry point
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	if (process.env.PI_SUBAGENT_CHILD === "1") return;
	let snapshot: SettingsSnapshot | null = null;
	let settingsPath: string | null = null;

	// ── session_start: snapshot original settings ──
	pi.on("session_start", async (_event, ctx) => {
		settingsPath = resolveSettingsPath(ctx.cwd);
		if (!settingsPath) return; // No settings to protect

		// Crash recovery: if .bak exists, restore from it first
		const bakPath = settingsPath + ".bak";
		if (existsSync(bakPath)) {
			const bakContent = readFileSync(bakPath, "utf-8");
			const currentContent = readFileSync(settingsPath, "utf-8");
			if (bakContent !== currentContent) {
				writeFileSync(settingsPath, bakContent, "utf-8");
			}
		}

		// Snapshot current values
		const settings = readSettings(settingsPath);
		snapshot = snapshotSettings(settings);

		// Create .bak for crash recovery
		writeSettings(bakPath, { ...settings, ...snapshot });
	});

	// ── model_select: restore only defaultModel/defaultProvider ──
	pi.on("model_select", async () => {
		if (!settingsPath || !snapshot) return;
		restoreSettings(settingsPath, snapshot, ["defaultModel", "defaultProvider"]);
	});

	// ── thinking_level_select: restore only defaultThinkingLevel ──
	pi.on("thinking_level_select", async () => {
		if (!settingsPath || !snapshot) return;
		restoreSettings(settingsPath, snapshot, ["defaultThinkingLevel"]);
	});

	// ── tool_call("subagent"): inject current model ──
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "subagent") return undefined;
		if (!ctx.model) return undefined;

		const input = event.input as Record<string, unknown>;

		const modelStr = `${ctx.model.provider}/${ctx.model.id}`;
		const thinking = pi.getThinkingLevel();
		const modelWithThinking =
			thinking && thinking !== "off" ? `${modelStr}:${thinking}` : modelStr;

		// Inject at top level (single agent mode)
		if (!input.model) {
			input.model = modelWithThinking;
		}

		// Inject into parallel tasks
		if (Array.isArray(input.tasks)) {
			for (const task of input.tasks as Record<string, unknown>[]) {
				if (!task.model) {
					task.model = modelWithThinking;
				}
			}
		}

		// Inject into chain steps
		if (Array.isArray(input.chain)) {
			for (const step of input.chain as Record<string, unknown>[]) {
				if (!step.model) {
					step.model = modelWithThinking;
				}
				// Inject into chain → parallel tasks
				if (Array.isArray(step.parallel)) {
					for (const ptask of step.parallel as Record<string, unknown>[]) {
						if (!ptask.model) {
							ptask.model = modelWithThinking;
						}
					}
				}
			}
		}

		return undefined;
	});

	// ── session_shutdown: cleanup .bak only (no restore) ──
	pi.on("session_shutdown", async () => {
		// model_select/thinking_level_select already restored during session.
		// Do NOT restore here — that would overwrite manual user edits.
		if (settingsPath) {
			const bakPath = settingsPath + ".bak";
			try {
				unlinkSync(bakPath);
			} catch {
				// Best effort — file may already be deleted
			}
		}
	});
}
