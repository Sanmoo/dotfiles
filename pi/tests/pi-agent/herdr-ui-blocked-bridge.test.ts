import { describe, expect, it } from "bun:test";
import {
	BLOCKED_LABEL,
	DIALOG_METHODS,
	wrapUiForHerdrBlocked,
} from "../../.pi/agent/extensions/00-herdr-ui-blocked-bridge";

type EmittedEvent = {
	name: string;
	data: unknown;
};

function createFakePi() {
	const events: EmittedEvent[] = [];
	return {
		events,
		pi: {
			events: {
				emit(name: string, data: unknown) {
					events.push({ name, data });
				},
			},
		},
	};
}

describe("herdr-ui-blocked-bridge", () => {
	it("wraps explicit dialog methods and preserves their return values", async () => {
		const { pi, events } = createFakePi();
		const ui = {
			async select(label: string, choices: string[]) {
				return `${label}:${choices[0]}`;
			},
		};

		wrapUiForHerdrBlocked(pi, ui);

		const result = await ui.select("Pick", ["A", "B"]);

		expect(result).toBe("Pick:A");
		expect(events).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: BLOCKED_LABEL },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("emits inactive when the original dialog throws and preserves the error", async () => {
		const { pi, events } = createFakePi();
		const expectedError = new Error("dialog failed");
		const ui = {
			async confirm() {
				throw expectedError;
			},
		};

		wrapUiForHerdrBlocked(pi, ui);

		await expect(ui.confirm()).rejects.toBe(expectedError);
		expect(events).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: BLOCKED_LABEL },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("is idempotent for an already wrapped ui object", async () => {
		const { pi, events } = createFakePi();
		const ui: {
			input: () => Promise<string>;
			confirm?: () => Promise<boolean>;
		} = {
			async input() {
				return "typed value";
			},
		};

		wrapUiForHerdrBlocked(pi, ui);
		expect(Object.getOwnPropertySymbols(ui)).toContain(
			Symbol.for("herdr-ui-blocked-bridge.ui-wrapped"),
		);
		ui.confirm = async () => true;
		wrapUiForHerdrBlocked(pi, ui);

		await expect(ui.input()).resolves.toBe("typed value");
		await expect(ui.confirm()).resolves.toBe(true);
		expect(events).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: BLOCKED_LABEL },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("does not throw when the ui object is frozen", () => {
		const { pi } = createFakePi();
		const ui = Object.freeze({
			async select() {
				return "choice";
			},
		});

		expect(() => wrapUiForHerdrBlocked(pi, ui)).not.toThrow();
	});

	it("does not throw when dialog property accessors or proxies throw", () => {
		const { pi } = createFakePi();
		const accessorUi = Object.defineProperty({}, "confirm", {
			get() {
				throw new Error("access denied");
			},
		});
		const proxyUi = new Proxy(
			{},
			{
				get() {
					throw new Error("proxy get denied");
				},
			},
		);

		expect(() => wrapUiForHerdrBlocked(pi, accessorUi)).not.toThrow();
		expect(() => wrapUiForHerdrBlocked(pi, proxyUi)).not.toThrow();
	});

	it("does not mark an object that initially has no dialog methods", async () => {
		const { pi, events } = createFakePi();
		const ui: { select?: () => Promise<string> } = {};

		wrapUiForHerdrBlocked(pi, ui);
		expect(Object.getOwnPropertySymbols(ui)).not.toContain(
			Symbol.for("herdr-ui-blocked-bridge.ui-wrapped"),
		);
		ui.select = async () => "late choice";
		wrapUiForHerdrBlocked(pi, ui);

		await expect(ui.select()).resolves.toBe("late choice");
		expect(events).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: BLOCKED_LABEL },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("wraps only explicit dialog methods and does not wrap custom", async () => {
		const { pi, events } = createFakePi();
		const ui = {
			async custom() {
				return "custom result";
			},
		};

		wrapUiForHerdrBlocked(pi, ui);

		const result = await ui.custom();

		expect(result).toBe("custom result");
		expect(events).toEqual([]);
		expect(Object.getOwnPropertySymbols(ui)).not.toContain(
			Symbol.for("herdr-ui-blocked-bridge.ui-wrapped"),
		);
		expect(DIALOG_METHODS).not.toContain("custom");
	});

	it("ignores emit failures without changing dialog behavior", async () => {
		const pi = {
			events: {
				emit() {
					throw new Error("no listeners available");
				},
			},
		};
		const ui = {
			async editor() {
				return "edited text";
			},
		};

		wrapUiForHerdrBlocked(pi, ui);

		await expect(ui.editor()).resolves.toBe("edited text");
	});
});
