import { describe, expect, it } from "bun:test";
import {
	buildSessionTitle,
	chooseTabLabel,
	createHerdrTabTitleController,
	parsePaneTabId,
	parseTabLabel,
	type HerdrCommandRunner,
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

function createFakeRunner(
	jsonResponses: Record<string, string | null>,
	runCalls: string[][],
): HerdrCommandRunner {
	return {
		async runJson(args) {
			return jsonResponses[args.join(" ")] ?? null;
		},
		async run(args) {
			runCalls.push([...args]);
			return true;
		},
	};
}

describe("buildSessionTitle", () => {
	it("prefixes an explicit session name with pi:", () => {
		expect(buildSessionTitle("Refactor auth")).toBe("pi: Refactor auth");
	});

	it("returns null for empty or blank names", () => {
		expect(buildSessionTitle("")).toBeNull();
		expect(buildSessionTitle("   ")).toBeNull();
		expect(buildSessionTitle(undefined)).toBeNull();
	});
});

describe("chooseTabLabel", () => {
	it("prefers the Pi session title when present", () => {
		expect(chooseTabLabel("Refactor auth", "dotfiles")).toBe(
			"pi: Refactor auth",
		);
	});

	it("falls back to the original Herdr label when no session name exists", () => {
		expect(chooseTabLabel("", "dotfiles")).toBe("dotfiles");
		expect(chooseTabLabel(undefined, "dotfiles")).toBe("dotfiles");
	});
});

describe("parsePaneTabId", () => {
	it("extracts tab_id from herdr pane get JSON", () => {
		expect(parsePaneTabId(PANE_INFO)).toBe("w6522c4796c52e1:1");
	});

	it("returns null for invalid JSON", () => {
		expect(parsePaneTabId("not-json")).toBeNull();
	});
});

describe("parseTabLabel", () => {
	it("extracts the visible tab label from herdr tab get JSON", () => {
		expect(parseTabLabel(TAB_INFO)).toBe("dotfiles");
	});

	it("returns null for invalid JSON", () => {
		expect(parseTabLabel("not-json")).toBeNull();
	});
});

describe("createHerdrTabTitleController", () => {
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
			["tab", "rename", "w6522c4796c52e1:1", "pi: Refactor auth"],
		]);
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
			["tab", "rename", "w6522c4796c52e1:1", "pi: Refactor auth"],
			["tab", "rename", "w6522c4796c52e1:1", "dotfiles"],
		]);
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
