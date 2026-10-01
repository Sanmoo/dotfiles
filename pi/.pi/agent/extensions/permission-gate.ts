/**
 * Permission Gate Extension
 *
 * Prompts for confirmation before running potentially dangerous bash commands.
 * Blocks by default in non-interactive mode (--print, --mode json, etc.).
 *
 * Patterns checked: rm -rf, sudo, chmod/chown 777, dd, fdisk, mkfs,
 * destructive redirects (>/dev/...), and pipe from curl/wget to shell.
 *
 * The prompt offers "Sim, e não perguntar novamente (perigo!)", which remembers
 * the exact command so that identical commands are never asked about again.
 * Exceptions are stored in <config-dir>/permission-gate-allowlist.json and can be
 * reviewed or revoked with /permission-gate.
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const CONFIRM_OPTION = "Sim";
const DENY_OPTION = "Não";
const REMEMBER_OPTION = "Sim, e não perguntar novamente (perigo!)";

const ALLOWLIST_FILE = "permission-gate-allowlist.json";
const ALLOWLIST_OBJECT_KEY = "commands";

function configDir(): string {
	const override = process.env.PI_CODING_AGENT_DIR?.trim();
	return override ? override : join(homedir(), ".pi", "agent");
}

function allowlistPath(): string {
	return join(configDir(), ALLOWLIST_FILE);
}

function summarizeCommand(command: string, maxLength = 72): string {
	const singleLine = command.replace(/\s+/g, " ").trim();
	return singleLine.length > maxLength ? `${singleLine.slice(0, maxLength - 1)}…` : singleLine;
}

function readAllowlist(): Set<string> {
	let raw: unknown;
	try {
		raw = JSON.parse(readFileSync(allowlistPath(), "utf-8"));
	} catch {
		// A missing or unreadable allowlist simply means nothing is allowed yet.
		return new Set();
	}

	const commands = (raw as Record<string, unknown> | null)?.[ALLOWLIST_OBJECT_KEY];
	if (!Array.isArray(commands)) return new Set();

	return new Set(commands.filter((entry): entry is string => typeof entry === "string"));
}

/** Returns a failure message when the allowlist could not be persisted. */
function writeAllowlist(commands: Set<string>): string | undefined {
	try {
		const path = allowlistPath();
		mkdirSync(dirname(path), { recursive: true });
		const payload = `${JSON.stringify({ [ALLOWLIST_OBJECT_KEY]: [...commands] }, null, 2)}\n`;
		writeFileSync(path, payload, "utf-8");
		return undefined;
	} catch (error) {
		return error instanceof Error ? error.message : String(error);
	}
}

export default function (pi: ExtensionAPI) {
	const emitHerdrBlocked = (data: { active: boolean; label?: string }) => {
		try {
			pi.events.emit("herdr:blocked", data);
		} catch {
			// Herdr status reporting is best-effort and must not affect permission gating.
		}
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
		description: "Revisar exceções: comandos liberados sem aviso",
		handler: async (args, ctx) => {
			const requested = args.trim().toLowerCase();

			if (requested === "clear" || requested === "limpar") {
				const failure = writeAllowlist(new Set());
				ctx.ui.notify(
					failure === undefined
						? "Exceções do permission-gate removidas."
						: `Não foi possível limpar as exceções: ${failure}`,
					failure === undefined ? "info" : "error",
				);
				return;
			}

			if (requested.length > 0) {
				ctx.ui.notify("Uso: /permission-gate [limpar]", "warning");
				return;
			}

			const allowed = readAllowlist();
			if (allowed.size === 0) {
				ctx.ui.notify("Nenhuma exceção do permission-gate registrada.", "info");
				return;
			}

			const commands = [...allowed];
			const clearAll = `Limpar todas (${commands.length})`;
			const options = [
				clearAll,
				...commands.map((command, index) => `${index + 1}. ${summarizeCommand(command)}`),
			];
			const choice = await ctx.ui.select(
				`Comandos liberados sem aviso:\n  ${allowlistPath()}\n\nSelecione um para revogar:`,
				options,
			);
			if (choice === undefined) return;

			const selected = commands[options.indexOf(choice) - 1];
			if (choice !== clearAll && selected === undefined) return;

			if (choice === clearAll) allowed.clear();
			else allowed.delete(selected as string);

			const failure = writeAllowlist(allowed);
			if (failure !== undefined) {
				ctx.ui.notify(`Não foi possível atualizar as exceções: ${failure}`, "error");
				return;
			}

			ctx.ui.notify(
				choice === clearAll
					? `Exceções do permission-gate removidas (${commands.length}).`
					: `Revogado: ${summarizeCommand(selected as string)}`,
				"info",
			);
		},
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		const isDangerous = dangerousPatterns.some((p) => p.test(command));

		if (!isDangerous) return undefined;

		const allowedCommands = readAllowlist();
		if (allowedCommands.has(command)) return undefined;

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
			allowedCommands.add(command);
			const failure = writeAllowlist(allowedCommands);
			if (failure !== undefined) {
				ctx.ui.notify(
					`Não foi possível salvar a exceção (${failure}). O comando foi liberado apenas desta vez.`,
					"warning",
				);
			}
			return undefined;
		}

		if (choice !== CONFIRM_OPTION) {
			return { block: true, reason: "Bloqueado pelo usuário" };
		}

		return undefined;
	});
}
