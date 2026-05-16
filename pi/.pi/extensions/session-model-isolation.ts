/**
 * Session Model Isolation Extension
 *
 * Prevents model/thinking changes from persisting to settings.json.
 * Captures a snapshot of the current model/thinking settings at session start
 * and restores them after every tool call, preventing accidental persistence
 * of temporary session changes.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
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
export interface SettingsSnapshot {
	defaultModel?: string;
	defaultProvider?: string;
	defaultThinkingLevel?: string;
}

/**
 * Read and parse a JSON settings file.
 */
export function readSettings(path: string): Record<string, unknown> {
	const raw = readFileSync(path, "utf-8");
	return JSON.parse(raw) as Record<string, unknown>;
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
	return {
		defaultModel: settings.defaultModel as string | undefined,
		defaultProvider: settings.defaultProvider as string | undefined,
		defaultThinkingLevel: settings.defaultThinkingLevel as string | undefined,
	};
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
): void {
	if (!existsSync(filePath)) return;

	const current = readSettings(filePath);
	let changed = false;

	for (const key of [
		"defaultModel",
		"defaultProvider",
		"defaultThinkingLevel",
	] as const) {
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
	let snapshot: SettingsSnapshot | null = null;
	let settingsPath: string | null = null;

	// ... handlers to be added in subsequent tasks
}
