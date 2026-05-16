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
	readdirSync,
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

/**
 * Extract a field value from YAML frontmatter in markdown text.
 * Returns the trimmed value, or undefined if frontmatter/field missing.
 */
function extractFrontmatterField(
	content: string,
	field: string,
): string | undefined {
	const match = content.match(/^---\n([\s\S]*?)\n---/);
	if (!match) return undefined;
	const fm = match[1];
	const re = new RegExp(`^${field}:\\s*(.+)$`, "m");
	const fmMatch = fm.match(re);
	return fmMatch?.[1]?.trim();
}

/**
 * Scan a directory for agent .md files with a `model` field in frontmatter.
 * Returns a Set of agent names that have models configured.
 */
function scanAgentDir(dir: string): Set<string> {
	const found = new Set<string>();
	if (!existsSync(dir)) return found;

	let entries: string[];
	try {
		entries = readdirSync(dir);
	} catch {
		return found;
	}

	for (const entry of entries) {
		if (!entry.endsWith(".md")) continue;
		const filePath = resolve(dir, entry);
		try {
			const content = readFileSync(filePath, "utf-8");
			const model = extractFrontmatterField(content, "model");
			if (model && model !== "false") {
				const name = entry.replace(/\.md$/, "");
				found.add(name);
			}
		} catch {
			// skip unreadable files
		}
	}
	return found;
}

/**
 * Read settings.json and extract agent names that have `model` defined
 * in `subagents.agentOverrides` (where model is a non-false string).
 */
function scanSettingsOverrides(cwd: string): Set<string> {
	const found = new Set<string>();
	const sp = resolveSettingsPath(cwd);
	if (!sp) return found;

	let settings: Record<string, unknown>;
	try {
		settings = readSettings(sp);
	} catch {
		return found;
	}

	const subagents = settings.subagents as Record<string, unknown> | undefined;
	if (!subagents || typeof subagents !== "object") return found;

	const overrides = subagents.agentOverrides as
		| Record<string, unknown>
		| undefined;
	if (!overrides || typeof overrides !== "object") return found;

	for (const [name, cfg] of Object.entries(overrides)) {
		if (cfg && typeof cfg === "object" && !Array.isArray(cfg)) {
			const model = (cfg as Record<string, unknown>).model;
			if (typeof model === "string") {
				found.add(name);
			}
		}
	}
	return found;
}

/**
 * Cache of agent names that have a `model` configured (frontmatter or settings).
 * Built once at session_start, then used for O(1) lookup in tool_call.
 */
let agentModelCache: Set<string> = new Set();

function buildAgentModelCache(cwd: string): void {
	agentModelCache = new Set<string>();

	// 1. User agents (~/.pi/agent/agents/)
	const userDir = resolve(homedir(), ".pi", "agent", "agents");
	for (const name of scanAgentDir(userDir)) agentModelCache.add(name);

	// 2. Project agents (.pi/agents/)
	const root = findProjectRoot(cwd);
	if (root) {
		const projDir = resolve(root, ".pi", "agents");
		for (const name of scanAgentDir(projDir)) agentModelCache.add(name);
	}

	// 3. Settings overrides (subagents.agentOverrides with model: string)
	for (const name of scanSettingsOverrides(cwd)) agentModelCache.add(name);
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

		// Build agent model cache (scanned once per session)
		buildAgentModelCache(ctx.cwd);
	});

	// ── model_select: restore only defaultModel/defaultProvider ──
	pi.on("model_select", async () => {
		if (!settingsPath || !snapshot) return;
		restoreSettings(settingsPath, snapshot, [
			"defaultModel",
			"defaultProvider",
		]);
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
		// Skip if agent already has model configured (checked via cache)
		const agentName = typeof input.agent === "string" ? input.agent : undefined;
		if (!input.model && !(agentName && agentModelCache.has(agentName))) {
			input.model = modelWithThinking;
		}

		// Inject into parallel tasks
		// Skip for tasks whose agent already has a model configured
		if (Array.isArray(input.tasks)) {
			for (const task of input.tasks as Record<string, unknown>[]) {
				if (!task.model) {
					const taskAgent =
						typeof task.agent === "string" ? task.agent : undefined;
					if (!taskAgent || !agentModelCache.has(taskAgent)) {
						task.model = modelWithThinking;
					}
				}
			}
		}

		// Inject into chain steps
		// Skip for steps whose agent already has a model configured
		if (Array.isArray(input.chain)) {
			for (const step of input.chain as Record<string, unknown>[]) {
				if (!step.model) {
					const stepAgent =
						typeof step.agent === "string" ? step.agent : undefined;
					if (!stepAgent || !agentModelCache.has(stepAgent)) {
						step.model = modelWithThinking;
					}
				}
				// Inject into chain → parallel tasks
				if (Array.isArray(step.parallel)) {
					for (const ptask of step.parallel as Record<string, unknown>[]) {
						if (!ptask.model) {
							const ptAgent =
								typeof ptask.agent === "string" ? ptask.agent : undefined;
							if (!ptAgent || !agentModelCache.has(ptAgent)) {
								ptask.model = modelWithThinking;
							}
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
