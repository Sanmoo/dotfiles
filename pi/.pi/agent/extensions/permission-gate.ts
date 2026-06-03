/**
 * Permission Gate Extension
 *
 * Prompts for confirmation before running potentially dangerous bash commands.
 * Blocks by default in non-interactive mode (--print, --mode json, etc.).
 *
 * Patterns checked: rm -rf, sudo, chmod/chown 777, dd, fdisk, mkfs,
 * destructive redirects (>/dev/...), and pipe from curl/wget to shell.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

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

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		const isDangerous = dangerousPatterns.some((p) => p.test(command));

		if (isDangerous) {
			if (!ctx.hasUI) {
				return {
					block: true,
					reason: "Comando perigoso bloqueado (modo não interativo)",
				};
			}

			let choice: string | undefined;
			emitHerdrBlocked({ active: true, label: "Aguardando permissão" });
			try {
				choice = await ctx.ui.select(
					`⚠️ Comando suspeito:\n\n  ${command}\n\nPermitir?`,
					["Sim", "Não"],
				);
			} finally {
				emitHerdrBlocked({ active: false });
			}

			if (choice !== "Sim") {
				return { block: true, reason: "Bloqueado pelo usuário" };
			}
		}

		return undefined;
	});
}
