/**
 * Herdr reporter for a sandboxed Pi.
 *
 * Runs inside the safe-pi container, where the pane's foreground process is
 * `docker`, so Herdr never detects Pi and the herdr-managed integration
 * (`herdr:pi`) is ignored. This extension reports the sandboxed Pi's state and
 * session reference to the mounted Herdr socket under its own source, which
 * Herdr applies to the pane regardless of its foreground process.
 *
 * It is a peer of the herdr-managed extension, not a replacement on the host:
 * the wrapper withholds the variables that activate the managed integration
 * (`HERDR_ENV`, `HERDR_SOCKET_PATH`, `HERDR_PANE_ID`) inside the sandbox and
 * hands this reporter the socket and pane under `SAFE_PI_HERDR_*` instead, so
 * exactly one source owns the pane. The state mapping matches the managed
 * integration — working during a turn, idle once settled, blocked while the
 * permission gate is open — so the sidebar behaves as it does for a host Pi.
 * Every report carries a monotonically increasing `seq`, so Herdr keeps the
 * newest state even when two reports overlap.
 *
 * Every report is best-effort. An unreachable socket, a refused write, or a
 * slow server is swallowed: reporting must never block, slow, or break Pi.
 *
 * The session reference is reported at the container-only sessions path. Herdr
 * stores the native `agent_session` reference only for its official `herdr:*`
 * sources, so a custom source never populates it. Automatic restore therefore
 * comes from the self-reported resume command this reporter attaches to every
 * report (`RESUME_ARGV`): Herdr has accepted `resume_argv` from a custom source
 * since 0.9.2 and persists it with the pane. After a Herdr server restart the
 * restored pane's shell gets that command typed into it in the saved working
 * directory, so the pane comes back inside a fresh sandbox rather than as a
 * plain shell or an unsandboxed Pi. Because the command rides on every report,
 * a changed session re-states it. If no report ever reaches Herdr, the pane has
 * no stored command and still fails closed to a shell.
 */

import net from "node:net";
import path from "node:path";

const SOURCE = "safe-pi";
const AGENT = "pi";
const REPORT_TIMEOUT_MS = 500;

/**
 * The resume command Herdr stores with the pane: re-enter the sandbox with the
 * most recent conversation in the pane's directory. It has to satisfy Herdr's
 * rules for a self-reported command — a bare first token resolved on the pane
 * shell's `PATH` (`safe-pi` resolves at `~/.local/bin`), at most 64 arguments
 * and 8 KiB, no apostrophes or control characters — because it runs on the host
 * in the pane's saved working directory, not inside the container.
 */
const RESUME_ARGV = ["safe-pi", "-c"];

interface SessionManager {
	getSessionFile?: () => string | undefined;
	getSessionId?: () => string | undefined;
}

interface SessionContext {
	mode?: string;
	isIdle?: () => boolean;
	sessionManager?: SessionManager;
}

interface HerdrBlockedEvent {
	active?: boolean;
	label?: string;
}

interface ExtensionAPI {
	events: {
		on(name: "herdr:blocked", handler: (data: HerdrBlockedEvent | undefined) => void): void;
	};
	on(
		name: "session_start" | "agent_start" | "agent_settled",
		handler: (event: { reason?: string } | undefined, ctx: SessionContext) => void,
	): void;
}

type AgentState = "working" | "blocked" | "idle";

function enabled(): boolean {
	return !!process.env.SAFE_PI_HERDR_SOCKET_PATH && !!process.env.SAFE_PI_HERDR_PANE_ID;
}

let reportSeq = Date.now() * 1000;

function nextReportSeq(): number {
	reportSeq += 1;
	return reportSeq;
}

/**
 * Send one request and forget about it. The socket and its timeout are
 * unreferenced so a pending report never keeps Pi alive, and every failure
 * path is ignored.
 */
function sendRequest(request: unknown): void {
	let socket: net.Socket | undefined;
	let timer: ReturnType<typeof setTimeout> | undefined;
	const finish = () => {
		if (timer) {
			clearTimeout(timer);
			timer = undefined;
		}
		try {
			socket?.destroy();
		} catch {
			// Best effort.
		}
	};

	try {
		socket = net.createConnection(process.env.SAFE_PI_HERDR_SOCKET_PATH as string);
		socket.unref?.();
		socket.on("error", finish);
		socket.on("end", finish);
		socket.on("close", finish);
		socket.on("connect", () => {
			try {
				socket?.write(`${JSON.stringify(request)}\n`);
			} catch {
				finish();
			}
		});
		socket.on("data", finish);

		timer = setTimeout(finish, REPORT_TIMEOUT_MS);
		timer.unref?.();
	} catch {
		finish();
	}
}

function requestId(kind: string): string {
	return `${SOURCE}:${kind}:${Date.now()}:${Math.random().toString(36).slice(2)}`;
}

export default function (pi: ExtensionAPI): void {
	if (!enabled()) {
		return;
	}

	let rootSession = false;
	let agentActive = false;
	let blockedCount = 0;
	let blockedMessage: string | undefined;
	let lastKey: string | undefined;

	let sessionPath: string | undefined;
	let sessionId: string | undefined;

	function updateSessionRef(ctx: SessionContext | undefined): void {
		try {
			const file = ctx?.sessionManager?.getSessionFile?.();
			sessionPath = typeof file === "string" && path.isAbsolute(file) ? file : undefined;
		} catch {
			sessionPath = undefined;
		}

		try {
			const id = ctx?.sessionManager?.getSessionId?.();
			sessionId = typeof id === "string" && id.length > 0 ? id : undefined;
		} catch {
			sessionId = undefined;
		}
	}

	function sessionRef(): Record<string, string> {
		if (sessionPath) {
			return { agent_session_path: sessionPath };
		}
		if (sessionId) {
			return { agent_session_id: sessionId };
		}
		return {};
	}

	function baseParams(): Record<string, unknown> {
		return {
			pane_id: process.env.SAFE_PI_HERDR_PANE_ID,
			source: SOURCE,
			agent: AGENT,
			seq: nextReportSeq(),
			resume_argv: RESUME_ARGV,
			...sessionRef(),
		};
	}

	function reportSession(sessionStartSource?: string): void {
		if (!sessionPath && !sessionId) {
			return;
		}
		sendRequest({
			id: requestId("session"),
			method: "pane.report_agent_session",
			params: {
				...baseParams(),
				session_start_source: sessionStartSource,
			},
		});
	}

	function desiredState(): { state: AgentState; message?: string } {
		if (blockedCount > 0) {
			return { state: "blocked", message: blockedMessage };
		}
		return agentActive ? { state: "working" } : { state: "idle" };
	}

	function publish(): void {
		const next = desiredState();
		const key = `${next.state}\u0000${next.message ?? ""}`;
		if (key === lastKey) {
			return;
		}
		lastKey = key;
		sendRequest({
			id: requestId("state"),
			method: "pane.report_agent",
			params: {
				...baseParams(),
				state: next.state,
				message: next.message,
			},
		});
	}

	pi.events.on("herdr:blocked", (data) => {
		try {
			if (!rootSession) {
				return;
			}
			if (data?.active) {
				blockedCount += 1;
				blockedMessage = data.label;
			} else {
				blockedCount = Math.max(0, blockedCount - 1);
				if (blockedCount === 0) {
					blockedMessage = undefined;
				}
			}
			publish();
		} catch {
			// Reporting never affects permission gating.
		}
	});

	pi.on("session_start", (event, ctx) => {
		try {
			// TUI only: RPC/JSON/print modes are headless and must not own a
			// pane Herdr can display.
			if (ctx?.mode !== "tui") {
				return;
			}
			rootSession = true;
			updateSessionRef(ctx);
			reportSession(event?.reason);
			agentActive = ctx?.isIdle?.() === false;
			publish();
		} catch {
			// Best effort.
		}
	});

	pi.on("agent_start", (_event, ctx) => {
		try {
			if (!rootSession) {
				return;
			}
			updateSessionRef(ctx);
			reportSession();
			agentActive = true;
			publish();
		} catch {
			// Best effort.
		}
	});

	pi.on("agent_settled", (_event, ctx) => {
		try {
			if (!rootSession || ctx?.isIdle?.() !== true) {
				return;
			}
			agentActive = false;
			publish();
		} catch {
			// Best effort.
		}
	});
}
