/**
 * Protected Paths Extension
 *
 * Blocks write and edit operations to sensitive files and directories.
 * Silent block in non-interactive mode, notification in TTY mode.
 *
 * Protected: .env, .ssh/, *.pem/*.key, node_modules/, lock files, .git/
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	const protectedPaths = [
		".env",
		".env.",
		".ssh/",
		".pem",
		".key",
		"node_modules/",
		"package-lock.json",
		"yarn.lock",
		"pnpm-lock.yaml",
		".git/",
		".dockerignore",
		"Dockerfile",
		"docker-compose",
		"id_rsa",
		"id_ed25519",
		".gnupg/",
		".config/",
	];

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write" && event.toolName !== "edit") {
			return undefined;
		}

		const path = event.input.path as string;
		const isProtected = protectedPaths.some((p) => path.includes(p));

		if (isProtected) {
			if (ctx.hasUI) {
				ctx.ui.notify(`🚫 Bloqueada escrita em caminho protegido: ${path}`, "warning");
			}
			return { block: true, reason: `"${path}" é um caminho protegido` };
		}

		return undefined;
	});
}
