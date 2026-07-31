import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
	formatInvalidModelMessage,
	sanitizeSessionName,
} from "../../.pi/agent/extensions/pi-auto-rename/utils";

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

describe("invalid model configuration message", () => {
	it("identifies model and config file to fix", () => {
		const message = formatInvalidModelMessage(
			"github-copilot",
			"gpt-4.1",
			"~/.pi/agent/extensions/pi-auto-rename.json",
		);

		expect(message).toBe(
			"pi-auto-rename: modelo inválido: github-copilot/gpt-4.1.\n" +
				"Corrija: ~/.pi/agent/extensions/pi-auto-rename.json",
		);
	});
});

describe("invalid model startup handling", () => {
	it("formats and reports invalid config before auto naming", () => {
		expect(extensionSource).toContain("formatInvalidModelMessage");
		expect(extensionSource).toContain('notify(ctx, message, "error")');
		expect(extensionSource).toContain("CONFIG_DISPLAY_PATH");
		expect(extensionSource).toContain("pi-auto-rename.json");
		expect(extensionSource).toContain("function validateConfiguredModel");
		expect(extensionSource).toContain("return false;");
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
