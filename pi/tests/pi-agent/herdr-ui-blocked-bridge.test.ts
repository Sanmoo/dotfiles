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

	it("is idempotent when the same ui object is wrapped more than once", async () => {
		const { pi, events } = createFakePi();
		const ui = {
			async input() {
				return "typed value";
			},
		};

		wrapUiForHerdrBlocked(pi, ui);
		wrapUiForHerdrBlocked(pi, ui);

		const result = await ui.input();

		expect(result).toBe("typed value");
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
