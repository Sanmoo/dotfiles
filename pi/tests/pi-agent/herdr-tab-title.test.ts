import { describe, expect, it } from "bun:test";
import {
	buildSessionTitle,
	chooseTabLabel,
	createHerdrTabTitleController,
	parsePaneTabId,
	parseTabLabel,
	registerHerdrTabTitle,
	type HerdrCommandRunner,
	type HerdrTabTitleController,
} from "../../.pi/agent/extensions/herdr-tab-title";

const PANE_INFO = JSON.stringify({
	id: "cli:pane:get",
	result: {
		type: "pane_info",
		pane: {
			pane_id: "w6522c4796c52e1-1",
			tab_id: "w6522c4796c52e1:1",
		},
	},
});

const PANE_INFO_WITH_INVALID_TAB_ID = JSON.stringify({
	id: "cli:pane:get",
	result: {
		type: "pane_info",
		pane: {
			pane_id: "w6522c4796c52e1-1",
			tab_id: 42,
		},
	},
});

const TAB_INFO = JSON.stringify({
	id: "cli:tab:get",
	result: {
		type: "tab_info",
		tab: {
			tab_id: "w6522c4796c52e1:1",
			label: "dotfiles",
		},
	},
});

const BLANK_TAB_INFO = JSON.stringify({
	id: "cli:tab:get",
	result: {
		type: "tab_info",
		tab: {
			tab_id: "w6522c4796c52e1:1",
			label: "",
		},
	},
});

function createFakeRunner(
	jsonResponses: Record<string, string | null>,
	runCalls: string[][],
	runResults: boolean[] = [],
): HerdrCommandRunner {
	return {
		async runJson(args) {
			return jsonResponses[args.join(" ")] ?? null;
		},
		async run(args) {
			runCalls.push([...args]);
			return runResults.shift() ?? true;
		},
	};
}

describe("buildSessionTitle", () => {
	it("returns an explicit session name without a prefix", () => {
		expect(buildSessionTitle("Refactor auth")).toBe("Refactor auth");
	});

	it("returns null for empty or blank names", () => {
		expect(buildSessionTitle("")).toBeNull();
		expect(buildSessionTitle("   ")).toBeNull();
		expect(buildSessionTitle(undefined)).toBeNull();
	});
});

describe("chooseTabLabel", () => {
	it("prefers the Pi session title when present", () => {
		expect(chooseTabLabel("Refactor auth", "dotfiles")).toBe("Refactor auth");
	});

	it("falls back to the original Herdr label when no session name exists", () => {
		expect(chooseTabLabel("", "dotfiles")).toBe("dotfiles");
		expect(chooseTabLabel(undefined, "dotfiles")).toBe("dotfiles");
	});

	it("preserves an intentionally blank original label", () => {
		expect(chooseTabLabel("", "")).toBe("");
	});
});

describe("parsePaneTabId", () => {
	it("extracts tab_id from herdr pane get JSON", () => {
		expect(parsePaneTabId(PANE_INFO)).toBe("w6522c4796c52e1:1");
	});

	it("returns null when tab_id is not a string", () => {
		expect(parsePaneTabId(PANE_INFO_WITH_INVALID_TAB_ID)).toBeNull();
	});

	it("returns null for invalid JSON", () => {
		expect(parsePaneTabId("not-json")).toBeNull();
	});
});

describe("parseTabLabel", () => {
	it("extracts the visible tab label from herdr tab get JSON", () => {
		expect(parseTabLabel(TAB_INFO)).toBe("dotfiles");
	});

	it("preserves an intentionally blank tab label", () => {
		expect(parseTabLabel(BLANK_TAB_INFO)).toBe("");
	});

	it("returns null for invalid JSON", () => {
		expect(parseTabLabel("not-json")).toBeNull();
	});
});

describe("createHerdrTabTitleController", () => {
	it("does nothing outside Herdr", async () => {
		const runCalls: string[][] = [];
		const runner = createFakeRunner(
			{
				"pane get p_1": PANE_INFO,
				"tab get w6522c4796c52e1:1": TAB_INFO,
			},
			runCalls,
		);

		const controller = createHerdrTabTitleController({
			env: {},
			runner,
		});

		await controller.initialize("Refactor auth");
		await controller.sync("Refactor auth");
		await controller.shutdown();

		expect(runCalls).toEqual([]);
		expect(controller.getState()).toEqual({
			enabled: false,
			tabId: null,
			originalTabLabel: null,
			lastAppliedLabel: null,
		});
	});

	it("does not rename when pane lookup fails", async () => {
		const runCalls: string[][] = [];
		const runner = createFakeRunner({}, runCalls);

		const controller = createHerdrTabTitleController({
			env: { HERDR_ENV: "1", HERDR_PANE_ID: "p_1" },
			runner,
		});

		await controller.initialize("Refactor auth");

		expect(runCalls).toEqual([]);
		expect(controller.getState()).toEqual({
			enabled: true,
			tabId: null,
			originalTabLabel: null,
			lastAppliedLabel: null,
		});
	});

	it("captures the current tab label without renaming when the session is unnamed", async () => {
		const runCalls: string[][] = [];
		const runner = createFakeRunner(
			{
				"pane get p_1": PANE_INFO,
				"tab get w6522c4796c52e1:1": TAB_INFO,
			},
			runCalls,
		);

		const controller = createHerdrTabTitleController({
			env: { HERDR_ENV: "1", HERDR_PANE_ID: "p_1" },
			runner,
		});

		await controller.initialize(undefined);

		expect(runCalls).toEqual([]);
		expect(controller.getState()).toEqual({
			enabled: true,
			tabId: "w6522c4796c52e1:1",
			originalTabLabel: "dotfiles",
			lastAppliedLabel: "dotfiles",
		});
	});

	it("renames the tab to the Pi title after initialization when the session is named", async () => {
		const runCalls: string[][] = [];
		const runner = createFakeRunner(
			{
				"pane get p_1": PANE_INFO,
				"tab get w6522c4796c52e1:1": TAB_INFO,
			},
			runCalls,
		);

		const controller = createHerdrTabTitleController({
			env: { HERDR_ENV: "1", HERDR_PANE_ID: "p_1" },
			runner,
		});

		await controller.initialize("Refactor auth");

		expect(runCalls).toEqual([
			["tab", "rename", "w6522c4796c52e1:1", "Refactor auth"],
		]);
	});

	it("retries a failed rename on the next sync", async () => {
		const runCalls: string[][] = [];
		const runner = createFakeRunner(
			{
				"pane get p_1": PANE_INFO,
				"tab get w6522c4796c52e1:1": TAB_INFO,
			},
			runCalls,
			[false, true],
		);

		const controller = createHerdrTabTitleController({
			env: { HERDR_ENV: "1", HERDR_PANE_ID: "p_1" },
			runner,
		});

		await controller.initialize("Refactor auth");
		await controller.sync("Refactor auth");

		expect(runCalls).toEqual([
			["tab", "rename", "w6522c4796c52e1:1", "Refactor auth"],
			["tab", "rename", "w6522c4796c52e1:1", "Refactor auth"],
		]);
		expect(controller.getState()).toEqual({
			enabled: true,
			tabId: "w6522c4796c52e1:1",
			originalTabLabel: "dotfiles",
			lastAppliedLabel: "Refactor auth",
		});
	});

	it("does not rename when the original tab label could not be captured", async () => {
		const runCalls: string[][] = [];
		const runner = createFakeRunner(
			{
				"pane get p_1": PANE_INFO,
			},
			runCalls,
		);

		const controller = createHerdrTabTitleController({
			env: { HERDR_ENV: "1", HERDR_PANE_ID: "p_1" },
			runner,
		});

		await controller.initialize("Refactor auth");

		expect(runCalls).toEqual([]);
		expect(controller.getState()).toEqual({
			enabled: true,
			tabId: "w6522c4796c52e1:1",
			originalTabLabel: null,
			lastAppliedLabel: null,
		});
	});

	it("restores the original label when the session name is cleared", async () => {
		const runCalls: string[][] = [];
		const runner = createFakeRunner(
			{
				"pane get p_1": PANE_INFO,
				"tab get w6522c4796c52e1:1": TAB_INFO,
			},
			runCalls,
		);

		const controller = createHerdrTabTitleController({
			env: { HERDR_ENV: "1", HERDR_PANE_ID: "p_1" },
			runner,
		});

		await controller.initialize("Refactor auth");
		await controller.sync("");

		expect(runCalls).toEqual([
			["tab", "rename", "w6522c4796c52e1:1", "Refactor auth"],
			["tab", "rename", "w6522c4796c52e1:1", "dotfiles"],
		]);
	});

	it("restores an intentionally blank original label on shutdown", async () => {
		const runCalls: string[][] = [];
		const runner = createFakeRunner(
			{
				"pane get p_1": PANE_INFO,
				"tab get w6522c4796c52e1:1": BLANK_TAB_INFO,
			},
			runCalls,
		);

		const controller = createHerdrTabTitleController({
			env: { HERDR_ENV: "1", HERDR_PANE_ID: "p_1" },
			runner,
		});

		await controller.initialize("Refactor auth");
		runCalls.length = 0;
		await controller.shutdown();

		expect(runCalls).toEqual([["tab", "rename", "w6522c4796c52e1:1", ""]]);
	});

	it("restores the original label on shutdown when Pi previously renamed the tab", async () => {
		const runCalls: string[][] = [];
		const runner = createFakeRunner(
			{
				"pane get p_1": PANE_INFO,
				"tab get w6522c4796c52e1:1": TAB_INFO,
			},
			runCalls,
		);

		const controller = createHerdrTabTitleController({
			env: { HERDR_ENV: "1", HERDR_PANE_ID: "p_1" },
			runner,
		});

		await controller.initialize("Refactor auth");
		runCalls.length = 0;
		await controller.shutdown();

		expect(runCalls).toEqual([
			["tab", "rename", "w6522c4796c52e1:1", "dotfiles"],
		]);
	});
});

describe("registerHerdrTabTitle", () => {
	it("starts polling after session_start and clears the poller on shutdown", async () => {
		const handlers: Record<string, (...args: any[]) => Promise<void>> = {};
		const calls: string[] = [];
		let sessionName = "Initial name";
		let pollCallback: (() => void | Promise<void>) | undefined;
		let clearedHandle: unknown;

		const controller: HerdrTabTitleController = {
			async initialize(name) {
				calls.push(`initialize:${name ?? ""}`);
			},
			async sync(name) {
				calls.push(`sync:${name ?? ""}`);
			},
			async shutdown() {
				calls.push("shutdown");
			},
			getState() {
				return {
					enabled: true,
					tabId: "w6522c4796c52e1:1",
					originalTabLabel: "dotfiles",
					lastAppliedLabel: "dotfiles",
				};
			},
		};

		const pi = {
			getSessionName() {
				return sessionName;
			},
			on(event: string, handler: (...args: any[]) => Promise<void>) {
				handlers[event] = handler;
			},
		};

		registerHerdrTabTitle(pi as any, () => controller, {
			setInterval(callback: () => void | Promise<void>) {
				pollCallback = callback;
				return 123;
			},
			clearInterval(handle: unknown) {
				clearedHandle = handle;
			},
			intervalMs: 250,
		} as any);

		await handlers.session_start({}, {} as any);
		sessionName = "Renamed session";
		await pollCallback?.();
		await handlers.session_shutdown({}, {} as any);

		expect(calls).toEqual([
			"initialize:Initial name",
			"sync:Renamed session",
			"shutdown",
		]);
		expect(clearedHandle).toBe(123);
	});
});
