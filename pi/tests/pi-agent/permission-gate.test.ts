import { describe, expect, it } from "bun:test";
import permissionGate from "../../.pi/agent/extensions/permission-gate";

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
		};
	},
) => Promise<unknown> | unknown;

type EmittedEvent = {
	name: string;
	data: unknown;
};

function setupPermissionGate(options?: { emitThrows?: boolean }) {
	let handler: ToolCallHandler | undefined;
	const emitted: EmittedEvent[] = [];

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
	};

	permissionGate(pi as never);

	if (!handler) {
		throw new Error("permission gate did not register a tool_call handler");
	}

	return { handler, emitted };
}

function bashEvent(command: string) {
	return {
		toolName: "bash",
		input: { command },
	};
}

function uiContext(
	select: (message: string, choices: string[]) => Promise<string | undefined>,
) {
	return {
		hasUI: true,
		ui: { select },
	};
}

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
				expect(choices).toEqual(["Sim", "Não"]);
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

		const result = await handler(bashEvent("sudo id"), {
			hasUI: false,
			ui: {
				select: async () => {
					throw new Error("select should not be called without UI");
				},
			},
		});

		expect(result).toEqual({
			block: true,
			reason: "Comando perigoso bloqueado (modo não interativo)",
		});
		expect(emitted).toEqual([]);
	});

	it("continues permission prompt behavior when Herdr event emission fails", async () => {
		const { handler, emitted } = setupPermissionGate({ emitThrows: true });

		const result = await handler(
			bashEvent("sudo id"),
			uiContext(async () => "Sim"),
		);

		expect(result).toBeUndefined();
		expect(emitted).toEqual([]);
	});
});
