import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import permissionGate from "../../.pi/agent/extensions/permission-gate";

const REMEMBER_OPTION = "Sim, e não perguntar novamente (perigo!)";
const PROMPT_OPTIONS = ["Sim", "Não", REMEMBER_OPTION];
const ALLOWLIST_FILE = "permission-gate-allowlist.json";

type ToolCallHandler = (
	event: {
		toolName: string;
		input: { command?: string };
	},
	ctx: {
		hasUI: boolean;
		ui: {
			select: (
				message: string,
				choices: string[],
			) => Promise<string | undefined>;
		},
	},
) => Promise<unknown> | unknown;

type Notification = { message: string; type?: "info" | "warning" | "error" };

type EmittedEvent = {
	name: string;
	data: unknown;
};

function setupPermissionGate(options?: { emitThrows?: boolean }) {
	let handler: ToolCallHandler | undefined;
	const emitted: EmittedEvent[] = [];
	const commands = new Map<
		string,
		(args: string, ctx: unknown) => Promise<void>
	>();

	const pi = {
		events: {
			emit(name: string, data: unknown) {
				if (options?.emitThrows) {
					throw new Error("emit failed");
				}
				emitted.push({ name, data });
			},
		},
		on(name: string, callback: ToolCallHandler) {
			expect(name).toBe("tool_call");
			handler = callback;
		},
		registerCommand(
			name: string,
			options: { handler: (args: string, ctx: unknown) => Promise<void> },
		) {
			commands.set(name, options.handler);
		},
	};

	permissionGate(pi as never);

	if (!handler) {
		throw new Error("permission gate did not register a tool_call handler");
	}

	return { handler, emitted, commands };
}

function bashEvent(command: string) {
	return {
		toolName: "bash",
		input: { command },
	};
}

function uiContext(
	select: (message: string, choices: string[]) => Promise<string | undefined>,
	notifications: Notification[] = [],
) {
	return {
		hasUI: true,
		ui: {
			select,
			notify(message: string, type?: "info" | "warning" | "error") {
				notifications.push({ message, type });
			},
		},
	};
}

function noUiContext(notifications: Notification[] = []) {
	return {
		hasUI: false,
		ui: {
			select: async () => {
				throw new Error("select should not be called without UI");
			},
			notify(message: string, type?: "info" | "warning" | "error") {
				notifications.push({ message, type });
			},
		},
	};
}

function allowlistFile(): string {
	return join(process.env.PI_CODING_AGENT_DIR!, ALLOWLIST_FILE);
}

function readAllowlistFile(): string[] {
	return JSON.parse(readFileSync(allowlistFile(), "utf-8")).commands;
}

function seedAllowlist(commands: string[]) {
	writeFileSync(allowlistFile(), JSON.stringify({ commands }), "utf-8");
}

let configDir: string;
const originalConfigDir = process.env.PI_CODING_AGENT_DIR;

beforeEach(() => {
	configDir = mkdtempSync(join(tmpdir(), "permission-gate-test-"));
	process.env.PI_CODING_AGENT_DIR = configDir;
});

afterEach(() => {
	if (originalConfigDir === undefined) {
		delete process.env.PI_CODING_AGENT_DIR;
	} else {
		process.env.PI_CODING_AGENT_DIR = originalConfigDir;
	}
	rmSync(configDir, { recursive: true, force: true });
});

describe("permission-gate", () => {
	it("does not block safe bash commands or emit Herdr blocked events", async () => {
		const { handler, emitted } = setupPermissionGate();

		const result = await handler(
			bashEvent("echo hello"),
			uiContext(async () => {
				throw new Error("select should not be called for safe commands");
			}),
		);

		expect(result).toBeUndefined();
		expect(emitted).toEqual([]);
	});

	it("emits Herdr blocked while waiting for permission and allows when user selects Sim", async () => {
		const { handler, emitted } = setupPermissionGate();
		const promptEvents: string[] = [];

		const result = await handler(
			bashEvent("sudo id"),
			uiContext(async (message, choices) => {
				promptEvents.push(message);
				expect(choices).toEqual(PROMPT_OPTIONS);
				expect(emitted).toEqual([
					{
						name: "herdr:blocked",
						data: { active: true, label: "Aguardando permissão" },
					},
				]);
				return "Sim";
			}),
		);

		expect(result).toBeUndefined();
		expect(promptEvents).toHaveLength(1);
		expect(promptEvents[0]).toContain("sudo id");
		expect(emitted).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: "Aguardando permissão" },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("clears Herdr blocked and blocks command when user selects Não", async () => {
		const { handler, emitted } = setupPermissionGate();

		const result = await handler(
			bashEvent("rm -rf build"),
			uiContext(async () => "Não"),
		);

		expect(result).toEqual({ block: true, reason: "Bloqueado pelo usuário" });
		expect(emitted).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: "Aguardando permissão" },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("clears Herdr blocked when permission prompt throws", async () => {
		const { handler, emitted } = setupPermissionGate();
		const expectedError = new Error("prompt failed");

		await expect(
			handler(
				bashEvent("sudo id"),
				uiContext(async () => {
					throw expectedError;
				}),
			),
		).rejects.toBe(expectedError);

		expect(emitted).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: "Aguardando permissão" },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("blocks dangerous commands without UI and emits no Herdr blocked events", async () => {
		const { handler, emitted } = setupPermissionGate();

		const result = await handler(bashEvent("sudo id"), noUiContext());

		expect(result).toEqual({
			block: true,
			reason: "Comando perigoso bloqueado (modo não interativo)",
		});
		expect(emitted).toEqual([]);
	});

	it("continues permission prompt behavior when Herdr event emission fails", async () => {
		const { handler, emitted } = setupPermissionGate({ emitThrows: true });
		let selectCalls = 0;

		const result = await handler(
			bashEvent("sudo id"),
			uiContext(async (_message, choices) => {
				selectCalls += 1;
				expect(choices).toEqual(PROMPT_OPTIONS);
				return "Sim";
			}),
		);

		expect(result).toBeUndefined();
		expect(selectCalls).toBe(1);
		expect(emitted).toEqual([]);
	});

	it("remembers the exact command when user selects the remember option", async () => {
		const { handler, emitted } = setupPermissionGate();

		const result = await handler(
			bashEvent("sudo id"),
			uiContext(async (_message, choices) => {
				expect(choices).toEqual(PROMPT_OPTIONS);
				return REMEMBER_OPTION;
			}),
		);

		expect(result).toBeUndefined();
		expect(readAllowlistFile()).toEqual(["sudo id"]);
		expect(emitted).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: "Aguardando permissão" },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("does not prompt again for a remembered command", async () => {
		const { handler, emitted } = setupPermissionGate();

		await handler(
			bashEvent("sudo id"),
			uiContext(async () => REMEMBER_OPTION),
		);
		emitted.length = 0;

		const result = await handler(
			bashEvent("sudo id"),
			uiContext(async () => {
				throw new Error("select should not be called for remembered commands");
			}),
		);

		expect(result).toBeUndefined();
		expect(emitted).toEqual([]);
	});

	it("still prompts for a dangerous command that is not the remembered one", async () => {
		seedAllowlist(["sudo id"]);
		const { handler } = setupPermissionGate();

		const result = await handler(
			bashEvent("sudo whoami"),
			uiContext(async (_message, choices) => {
				expect(choices).toEqual(PROMPT_OPTIONS);
				return "Não";
			}),
		);

		expect(result).toEqual({ block: true, reason: "Bloqueado pelo usuário" });
		expect(readAllowlistFile()).toEqual(["sudo id"]);
	});

	it("allows remembered commands in non-interactive mode but still blocks the rest", async () => {
		seedAllowlist(["sudo id"]);
		const { handler } = setupPermissionGate();

		expect(await handler(bashEvent("sudo id"), noUiContext())).toBeUndefined();
		expect(await handler(bashEvent("rm -rf /"), noUiContext())).toEqual({
			block: true,
			reason: "Comando perigoso bloqueado (modo não interativo)",
		});
	});

	it("ignores a corrupted allowlist file instead of failing open", async () => {
		writeFileSync(allowlistFile(), "not json", "utf-8");
		const { handler } = setupPermissionGate();

		const result = await handler(
			bashEvent("sudo id"),
			uiContext(async (_message, choices) => {
				expect(choices).toEqual(PROMPT_OPTIONS);
				return "Não";
			}),
		);

		expect(result).toEqual({ block: true, reason: "Bloqueado pelo usuário" });
	});

	it("keeps prompting when the allowlist cannot be persisted", async () => {
		const blockedDir = join(configDir, "not-a-directory");
		writeFileSync(blockedDir, "", "utf-8");
		process.env.PI_CODING_AGENT_DIR = blockedDir;

		const { handler } = setupPermissionGate();
		const notifications: Notification[] = [];
		let prompted = 0;

		const chooseRemember = uiContext(async (_message, choices) => {
			prompted += 1;
			expect(choices).toEqual(PROMPT_OPTIONS);
			return REMEMBER_OPTION;
		}, notifications);

		expect(await handler(bashEvent("sudo id"), chooseRemember)).toBeUndefined();
		expect(prompted).toBe(1);
		expect(notifications).toHaveLength(1);
		expect(notifications[0]?.type).toBe("warning");

		// The exception was not stored, so the next identical command prompts again.
		expect(await handler(bashEvent("sudo id"), chooseRemember)).toBeUndefined();
		expect(prompted).toBe(2);
	});

	it("clears all exceptions through /permission-gate limpar", async () => {
		seedAllowlist(["sudo id", "rm -rf build"]);
		const { commands } = setupPermissionGate();
		const notifications: Notification[] = [];

		await commands.get("permission-gate")!("limpar", uiContext(async () => undefined, notifications));

		expect(readAllowlistFile()).toEqual([]);
		expect(notifications).toEqual([
			{ message: "Exceções do permission-gate removidas.", type: "info" },
		]);
	});

	it("revokes a single exception through the /permission-gate selector", async () => {
		seedAllowlist(["sudo id", "rm -rf build"]);
		const { commands } = setupPermissionGate();
		const notifications: Notification[] = [];

		await commands.get("permission-gate")!(
			"",
			uiContext(async (_message, choices) => {
				expect(choices).toEqual(["Limpar todas (2)", "1. sudo id", "2. rm -rf build"]);
				return "1. sudo id";
			}, notifications),
		);

		expect(readAllowlistFile()).toEqual(["rm -rf build"]);
		expect(notifications).toEqual([{ message: "Revogado: sudo id", type: "info" }]);
	});

	it("reports when there are no exceptions to review", async () => {
		const { commands } = setupPermissionGate();
		const notifications: Notification[] = [];

		await commands.get("permission-gate")!(
			"",
			uiContext(async () => {
				throw new Error("select should not be called without exceptions");
			}, notifications),
		);

		expect(notifications).toEqual([
			{ message: "Nenhuma exceção do permission-gate registrada.", type: "info" },
		]);
	});
});
