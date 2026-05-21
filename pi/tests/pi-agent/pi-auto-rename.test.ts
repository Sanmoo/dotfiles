import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { sanitizeSessionName } from "../../.pi/agent/extensions/pi-auto-rename/utils";

const extensionSource = readFileSync(
	join(import.meta.dir, "../../.pi/agent/extensions/pi-auto-rename/index.ts"),
	"utf8",
);

describe("pi-auto-rename local prompts", () => {
	it("asks for a descriptive one-line title instead of a 2-6 word title", () => {
		expect(extensionSource).not.toContain("Use 2-6 words");
		expect(extensionSource).toContain("descriptive one-line session title");
		expect(extensionSource).toContain("up to 18 words");
	});
});

describe("sanitizeSessionName", () => {
	it("allows a full-line session title up to 160 characters", () => {
		const title = "A".repeat(150);

		expect(sanitizeSessionName(title)).toBe(title);
	});

	it("truncates titles longer than 160 characters", () => {
		const title = "B".repeat(170);

		expect(sanitizeSessionName(title)).toHaveLength(160);
	});
});
