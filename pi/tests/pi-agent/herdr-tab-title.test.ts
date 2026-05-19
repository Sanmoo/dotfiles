import { describe, expect, it } from "bun:test";
import {
	buildSessionTitle,
	chooseTabLabel,
	parsePaneTabId,
	parseTabLabel,
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
