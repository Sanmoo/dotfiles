import { afterEach, describe, expect, it } from "bun:test";
import {
	existsSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import sessionModelIsolation from "../../.pi/agent/extensions/session-model-isolation";

type EventHandler = (event: unknown, ctx: unknown) => Promise<unknown> | unknown;

/**
 * The extension resolves settings through the project `.pi/settings.json` first,
 * so each case runs inside a throwaway project directory: the real
 * `~/.pi/agent/settings.json` is never touched.
 */
function createProject(settings: Record<string, unknown>, bak?: string) {
	const root = mkdtempSync(join(tmpdir(), "session-model-isolation-"));
	const projectDir = join(root, "project");
	const settingsPath = join(projectDir, ".pi", "settings.json");
	mkdirSync(join(projectDir, ".pi"), { recursive: true });
	writeFileSync(settingsPath, `${JSON.stringify(settings, null, 2)}\n`, "utf-8");
	if (bak !== undefined) {
		writeFileSync(`${settingsPath}.bak`, bak, "utf-8");
	}
	cleanupDirs.push(root);
	return { projectDir, settingsPath, bakPath: `${settingsPath}.bak` };
}

function setupExtension() {
	const handlers = new Map<string, EventHandler>();
	const pi = {
		on(name: string, callback: EventHandler) {
			handlers.set(name, callback);
		},
		getThinkingLevel() {
			return "medium";
		},
	};
	// The extension is deliberately inert inside a Pi subagent session
	// (PI_SUBAGENT_CHILD=1): it registers no handlers at all. These tests assert
	// the handlers' behaviour, so they must control that ambient variable rather
	// than inherit whichever session happens to run the suite. Remove it around
	// registration, then restore whatever was there.
	const savedSubagentChild = process.env.PI_SUBAGENT_CHILD;
	delete process.env.PI_SUBAGENT_CHILD;
	try {
		sessionModelIsolation(pi as never);
	} finally {
		if (savedSubagentChild === undefined) {
			delete process.env.PI_SUBAGENT_CHILD;
		} else {
			process.env.PI_SUBAGENT_CHILD = savedSubagentChild;
		}
	}
	const sessionStart = handlers.get("session_start");
	const sessionShutdown = handlers.get("session_shutdown");
	if (!sessionStart || !sessionShutdown) {
		throw new Error("extension did not register session handlers");
	}
	return { sessionStart, sessionShutdown };
}

function readSettingsFile(path: string): Record<string, unknown> {
	return JSON.parse(readFileSync(path, "utf-8"));
}

const cleanupDirs: string[] = [];

afterEach(() => {
	for (const dir of cleanupDirs.splice(0)) {
		rmSync(dir, { recursive: true, force: true });
	}
});

describe("session-model-isolation crash recovery", () => {
	it("keeps settings keys the extension does not protect", async () => {
		const { projectDir, settingsPath } = createProject(
			{ defaultModel: "current/model", defaultTools: ["+codemode"] },
			// Stale snapshot: taken before defaultTools was added by hand.
			`${JSON.stringify({ defaultModel: "old/model", defaultTools: [] }, null, 2)}\n`,
		);
		const { sessionStart } = setupExtension();

		await sessionStart({}, { cwd: projectDir });

		const settings = readSettingsFile(settingsPath);
		expect(settings.defaultTools).toEqual(["+codemode"]);
	});

	it("restores the protected model and thinking keys from the snapshot", async () => {
		const { projectDir, settingsPath } = createProject(
			{
				defaultModel: "mutated/model",
				defaultProvider: "mutated",
				defaultThinkingLevel: "low",
				defaultTools: ["+codemode"],
			},
			`${JSON.stringify(
				{
					defaultModel: "original/model",
					defaultProvider: "original",
					defaultThinkingLevel: "high",
					defaultTools: [],
				},
				null,
				2,
			)}\n`,
		);
		const { sessionStart } = setupExtension();

		await sessionStart({}, { cwd: projectDir });

		const settings = readSettingsFile(settingsPath);
		expect(settings.defaultModel).toBe("original/model");
		expect(settings.defaultProvider).toBe("original");
		expect(settings.defaultThinkingLevel).toBe("high");
		expect(settings.defaultTools).toEqual(["+codemode"]);
	});

	it("leaves the current settings intact when the snapshot is unreadable", async () => {
		const settings = {
			defaultModel: "current/model",
			defaultTools: ["+codemode"],
		};
		const { projectDir, settingsPath } = createProject(
			settings,
			"{ this is not json",
		);
		const { sessionStart } = setupExtension();

		await sessionStart({}, { cwd: projectDir });

		expect(readSettingsFile(settingsPath)).toEqual(settings);
	});

	it("writes a snapshot at session start and removes it at shutdown", async () => {
		const settings = { defaultModel: "current/model" };
		const { projectDir, settingsPath, bakPath } = createProject(settings);
		const { sessionStart, sessionShutdown } = setupExtension();

		await sessionStart({}, { cwd: projectDir });

		expect(existsSync(bakPath)).toBe(true);
		expect(readSettingsFile(bakPath).defaultModel).toBe("current/model");

		await sessionShutdown({}, { cwd: projectDir });

		expect(existsSync(bakPath)).toBe(false);
		expect(readSettingsFile(settingsPath).defaultModel).toBe("current/model");
	});
});
