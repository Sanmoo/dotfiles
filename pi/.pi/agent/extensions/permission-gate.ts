/**
 * Permission Gate Extension
 *
 * Prompts for confirmation before running potentially dangerous bash commands.
 * Blocks by default in non-interactive mode (--print, --mode json, etc.).
 *
 * Patterns checked: rm -rf, sudo, chmod/chown 777, dd, fdisk, mkfs,
 * destructive redirects (>/dev/...), and pipe from curl/wget to shell.
 *
 * The prompt offers "Sim, e não perguntar novamente (perigo!)", which turns on
 * YOLO mode for the current session: this extension stops confirming any command
 * until the session ends. The toggle is recorded as a session entry, so it is
 * restored on /reload and on branch navigation, but it never leaves the session
 * and it is ignored without a UI (non-interactive runs keep failing closed).
 *
 * YOLO mode shows a footer status and can be inspected or toggled with
 * /permission-gate: there, on/off describe the gate itself, so "on" restores the
 * confirmations and "off" silences them for the rest of the session.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const CONFIRM_OPTION = "Sim";
const DENY_OPTION = "Não";
const REMEMBER_OPTION = "Sim, e não perguntar novamente (perigo!)";

const YOLO_ENTRY_TYPE = "permission-gate-yolo";
const YOLO_STATUS_KEY = "permission-gate";
const YOLO_STATUS_TEXT = "⚠ YOLO: sem confirmações";

interface YoloState {
	active: boolean;
}

const USAGE =
	"Uso: /permission-gate [on|off] — on volta a pedir confirmação, off desliga os avisos (YOLO)";
/** "on" is about the gate: the warnings are on, so dangerous commands ask again. */
const GATE_ON_ARGS = new Set(["on", "ask", "perguntar"]);
/** "off" is about the gate: the warnings are off, so YOLO mode takes over. */
const GATE_OFF_ARGS = new Set(["off", "yolo"]);

export default function (pi: ExtensionAPI) {
	let yoloActive = false;

	const emitHerdrBlocked = (data: { active: boolean; label?: string }) => {
		try {
			pi.events.emit("herdr:blocked", data);
		} catch {
			// Herdr status reporting is best-effort and must not affect permission gating.
		}
	};

	const publishYoloStatus = (ctx: ExtensionContext) => {
		if (!ctx.hasUI) return;
		ctx.ui.setStatus(YOLO_STATUS_KEY, yoloActive ? YOLO_STATUS_TEXT : undefined);
	};

	const setYoloMode = (active: boolean, ctx: ExtensionContext) => {
		yoloActive = active;
		pi.appendEntry<YoloState>(YOLO_ENTRY_TYPE, { active });
		publishYoloStatus(ctx);
	};

	// The toggle lives in the session branch, so /reload and branch navigation keep
	// it consistent with the active history. Without a UI there is nobody to
	// approve a dangerous command, so YOLO stays off.
	const restoreYoloMode = (ctx: ExtensionContext) => {
		let restored = false;
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "custom" && entry.customType === YOLO_ENTRY_TYPE) {
				restored = (entry.data as YoloState | undefined)?.active === true;
			}
		}
		yoloActive = ctx.hasUI ? restored : false;
		publishYoloStatus(ctx);
	};

	const dangerousPatterns = [
		/\brm\s+(-rf?|--recursive)/i,
		/\bsudo\b/i,
		/\b(chmod|chown)\b.*777/i,
		/\bdd\b/i,
		/\bmkfs\./i,
		/\bfdisk\b/i,
		/\bparted\b/i,
		/>\s*\/dev\/(sd[a-z]|nvme[0-9]|vd[a-z]|mmcblk[0-9]|loop[0-9]|sr[0-9]|disk\/)/i,
		/\b(curl|wget)\b.*\|\s*(ba)?sh\b/i,
		/\b(>\|?)\s*\/etc\//i,
		/\bchattr\b/i,
	];

	pi.registerCommand("permission-gate", {
		description: "Mostrar ou alternar o modo YOLO (sem confirmações) desta sessão",
		handler: async (args, ctx) => {
			const requested = args.trim().toLowerCase();

			if (GATE_ON_ARGS.has(requested)) {
				setYoloMode(false, ctx);
				ctx.ui.notify("Avisos ligados: comandos perigosos voltam a pedir confirmação.", "info");
				return;
			}

			if (GATE_OFF_ARGS.has(requested)) {
				setYoloMode(true, ctx);
				ctx.ui.notify(
					"YOLO ativado: comandos perigosos rodam sem confirmação até o fim desta sessão.",
					"warning",
				);
				return;
			}

			if (requested.length > 0) {
				ctx.ui.notify(USAGE, "warning");
				return;
			}

			ctx.ui.notify(
				yoloActive
					? "YOLO ativo: esta extensão não confirma nenhum comando nesta sessão. Use /permission-gate on para voltar a pedir confirmação."
					: "Avisos ativos: comandos perigosos pedem confirmação. Use /permission-gate off para desligá-los (YOLO) nesta sessão.",
				"info",
			);
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		restoreYoloMode(ctx);
	});

	pi.on("session_tree", async (_event, ctx) => {
		restoreYoloMode(ctx);
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		const isDangerous = dangerousPatterns.some((p) => p.test(command));

		if (!isDangerous) return undefined;
		if (yoloActive) return undefined;

		if (!ctx.hasUI) {
			return {
				block: true,
				reason: "Comando perigoso bloqueado (modo não interativo)",
			};
		}

		let choice: string | undefined;
		emitHerdrBlocked({ active: true, label: "Aguardando permissão" });
		try {
			choice = await ctx.ui.select(`⚠️ Comando suspeito:\n\n  ${command}\n\nPermitir?`, [
				CONFIRM_OPTION,
				DENY_OPTION,
				REMEMBER_OPTION,
			]);
		} finally {
			emitHerdrBlocked({ active: false });
		}

		if (choice === REMEMBER_OPTION) {
			setYoloMode(true, ctx);
			ctx.ui.notify(
				"YOLO ativado: comandos perigosos rodam sem confirmação até o fim desta sessão.",
				"warning",
			);
			return undefined;
		}

		if (choice !== CONFIRM_OPTION) {
			return { block: true, reason: "Bloqueado pelo usuário" };
		}

		return undefined;
	});
}
