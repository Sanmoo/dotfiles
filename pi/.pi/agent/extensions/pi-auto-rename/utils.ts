import type { Message, TextContent } from "@earendil-works/pi-ai";
import type {
	SessionEntry,
	SessionMessageEntry,
} from "@earendil-works/pi-coding-agent";

const NAME_LENGTH_CAP = 160;

export function formatInvalidModelMessage(
	provider: string,
	id: string,
	configPath: string,
): string {
	return (
		`pi-auto-rename: modelo inválido: ${provider}/${id}.\n` +
		`Corrija: ${configPath}`
	);
}

// ─── Provider session attribution ─────────────────────────────────────────────

const OPENCODE_SESSION_HEADER = "x-opencode-session";
const OPENCODE_CLIENT_HEADER = "x-opencode-client";
const OPENCODE_HOST = "opencode.ai";

function matchesOpenCodeHost(baseUrl: unknown): boolean {
	try {
		return new URL(String(baseUrl ?? "")).hostname === OPENCODE_HOST;
	} catch {
		return false;
	}
}

/**
 * OpenCode routing headers for extension-initiated model calls.
 *
 * Pi merges these in its main agent loop, but `complete()` side-calls from
 * extensions dispatch directly and bypass that merge, which makes OpenCode
 * answer `400 MissingSessionID`. Returns undefined for every other provider so
 * non-OpenCode requests stay unchanged.
 */
export function openCodeSessionHeaders(
	model: { provider: string; baseUrl?: string | undefined },
	sessionId: string | undefined,
): Record<string, string> | undefined {
	if (!sessionId) return undefined;
	const isOpenCode =
		model.provider === "opencode" ||
		model.provider === "opencode-go" ||
		matchesOpenCodeHost(model.baseUrl);
	if (!isOpenCode) return undefined;
	return {
		[OPENCODE_SESSION_HEADER]: sessionId,
		[OPENCODE_CLIENT_HEADER]: "pi",
	};
}

// ─── Content extraction ───────────────────────────────────────────────────────

function isLlmMessage(
	entry: SessionEntry,
): entry is SessionMessageEntry & { message: Message } {
	if (entry.type !== "message") return false;
	const role = (entry as SessionMessageEntry).message.role;
	return role === "user" || role === "assistant" || role === "toolResult";
}

function extractText(content: Message["content"]): string {
	if (typeof content === "string") return content;
	const parts: string[] = [];
	for (const block of content) {
		if (block.type === "text") parts.push((block as TextContent).text);
	}
	return parts.join("\n");
}

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Find the earliest user message text in a session branch.
 * Branch entries arrive newest-first, so scan from the end.
 */
export function getFirstUserMessageText(
	entries: SessionEntry[],
): string | null {
	for (let i = entries.length - 1; i >= 0; i--) {
		const entry = entries[i];
		if (!entry || !isLlmMessage(entry)) continue;
		if (entry.message.role !== "user") continue;
		const text = extractText(entry.message.content).trim();
		if (text) return text;
	}
	return null;
}

/**
 * Build a chronological transcript of user/assistant messages.
 */
export function getConversationTranscript(entries: SessionEntry[]): string {
	const segments: string[] = [];
	for (let i = entries.length - 1; i >= 0; i--) {
		const entry = entries[i];
		if (!entry || !isLlmMessage(entry)) continue;
		const { role, content } = entry.message;
		if (role !== "user" && role !== "assistant") continue;
		const text = extractText(content).trim();
		if (!text) continue;
		segments.push(`${role === "user" ? "User" : "Assistant"}: ${text}`);
	}
	return segments.join("\n\n");
}

/**
 * Clean up a raw model response into a usable session name.
 */
export function sanitizeSessionName(raw: string): string {
	const firstLine = raw
		.split(/\r?\n/)
		.map((l) => l.trim())
		.find((l) => l.length > 0);
	if (!firstLine) return "";

	let name = firstLine
		.replace(/^["'`]+/, "")
		.replace(/["'`]+$/, "")
		.replace(/\s+/g, " ")
		.trim()
		.replace(/[.!?:;,]+$/, "");

	if (name.length > NAME_LENGTH_CAP)
		name = name.slice(0, NAME_LENGTH_CAP).trimEnd();
	return name;
}
