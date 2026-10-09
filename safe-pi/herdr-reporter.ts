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
 * integration — working during a turn, idle once settled, and blocked while a
 * `herdr:blocked` source is active — so the sidebar behaves as it does for a
 * host Pi. Inside the sandbox nothing emits `blocked`: the permission gate
 * registers nothing there, because the container is the boundary.
 * Every report carries a monotonically increasing `seq`, so Herdr keeps the
 * newest state even when two reports overlap.
 *
 * Every report is best-effort. An unreachable socket, a refused write, or a
 * slow server is swallowed: reporting must never break Pi, and only the release
 * on quit is awaited, bounded by `RELEASE_TIMEOUT_MS`.
 *
 * The pane is released when the sandboxed Pi quits: a `session_shutdown` with
 * reason `quit` (Ctrl-C twice, Ctrl-D, `/quit`, SIGTERM/SIGHUP) sends
 * `pane.release_agent`, awaited with a short deadline because Pi exits as soon
 * as the handler resolves. A session replacement (`resume`/`new`/`fork`) and an
 * extension reload keep the pane and report the new session instead.
 *
 * The reporter holds the pane with an agent label Herdr does not recognize
 * (`safe-pi`) rather than `pi`, and reports `display_agent: "Pi"` so the
 * sidebar keeps the name. Herdr arms its idle-shell safety net — clearing a
 * self-reported agent once the pane is back at its shell — only for a label it
 * cannot resolve to an agent it detects by process, so reporting `pi` would
 * leave the pane attributed after a container death that sends no shutdown
 * event.
 *
 * The session reference is reported at the container-only sessions path. Herdr
 * stores the native `agent_session` reference only for its official `herdr:*`
 * sources, so a custom source never populates it. Automatic restore therefore
 * comes from the self-reported resume command this reporter attaches to every
 * report (`resumeArgv`): Herdr has accepted `resume_argv` from a custom source
 * since 0.9.2 and persists it with the pane. After a Herdr server restart the
 * restored pane's shell gets that command typed into it in the saved working
 * directory, so the pane comes back inside a fresh sandbox rather than as a
 * plain shell or an unsandboxed Pi. The command names the session id, so a
 * restart cannot reopen a different conversation in the same directory. Because
 * the command rides on every report, a changed session re-states it. If no
 * report ever reaches Herdr, the pane has no stored command and still fails
 * closed to a shell.
 */

import net from "node:net";
import path from "node:path";

const SOURCE = "safe-pi";
/**
 * The agent label Herdr stores for this pane. It is deliberately not `pi`:
 * Herdr's idle-shell safety net is armed only for a self-reported agent whose
 * label it cannot resolve to an agent it detects by process
 * (`self_reported_agent_active` tests `parse_agent_label(label).is_none()`), so
 * reporting `pi` would leave the pane attributed forever when the container
 * dies without releasing. `DISPLAY_AGENT` keeps the visible name a Pi.
 */
const AGENT = "safe-pi";
const DISPLAY_AGENT = "Pi";
const REPORT_TIMEOUT_MS = 500;
/**
 * The deadline for the release sent on quit. Pi calls `process.exit(0)` as
 * soon as the shutdown handlers resolve, so the release is awaited; the cap
 * keeps an unreachable socket from delaying a quit by more than this.
 */
const RELEASE_TIMEOUT_MS = 250;

/**
 * Pi's session ids are UUIDs (alphanumerics plus `-`, `_`, `.`). Anything else
 * is refused before it can reach the resume command Herdr runs on the host or
 * the session reference the reporter stores, so a hand-edited session header
 * cannot smuggle a flag or a quote into either.
 */
function isSessionId(value: unknown): value is string {
	return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value);
}

/**
 * The resume command Herdr stores with the pane: re-enter the sandbox in the
 * conversation that was running, named by its session id. `-c` alone would be
 * enough only while the pane's directory holds a single session; naming the id
 * is what keeps a restart from reopening another one, and `safe-pi` forwards
 * `--session <id>` to a Pi that resolves it against the container-only project
 * session directory. With no id to name, it falls back to the most recent
 * conversation in that directory. The rules such a command has to satisfy are
 * stated in the module header, beside Herdr's other requirements.
 */
function resumeArgv(sessionId: string | undefined): string[] {
	if (sessionId) {
		return ["safe-pi", "--session", sessionId];
	}
	return ["safe-pi", "-c"];
}

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
		name: "session_start" | "agent_start" | "agent_settled" | "session_shutdown",
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

/**
 * Send one request and resolve once Herdr has answered, the connection has
 * ended, or the deadline passes. The socket is unreferenced so it never keeps
 * Pi alive, but the deadline timer is not: an awaited report is honoured even
 * when nothing else would keep the event loop running. Every failure path
 * resolves, so a report never throws.
 */
function sendRequestAndWait(request: unknown, timeoutMs: number): Promise<void> {
	return new Promise((resolve) => {
		let socket: net.Socket | undefined;
		let timer: ReturnType<typeof setTimeout> | undefined;
		let done = false;
		const finish = () => {
			if (done) {
				return;
			}
			done = true;
			if (timer) {
				clearTimeout(timer);
				timer = undefined;
			}
			try {
				socket?.destroy();
			} catch {
				// Best effort.
			}
			resolve();
		};

		try {
			socket = net.createConnection(process.env.SAFE_PI_HERDR_SOCKET_PATH as string);
			socket.unref?.();
			socket.on("error", finish);
			socket.on("end", finish);
			socket.on("close", finish);
			socket.on("data", finish);
			socket.on("connect", () => {
				try {
					socket?.write(`${JSON.stringify(request)}\n`);
				} catch {
					finish();
				}
			});

			timer = setTimeout(finish, timeoutMs);
		} catch {
			finish();
		}
	});
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
			sessionId = isSessionId(id) ? id : undefined;
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
			resume_argv: resumeArgv(sessionId),
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

	/**
	 * Herdr keeps the visible agent name separate from the authority label, so
	 * the reporter holds the pane with a label Herdr does not recognize (which
	 * is what keeps its idle-shell safety net armed) while the sidebar and
	 * border still read `Pi`.
	 */
	function reportMetadata(): void {
		sendRequest({
			id: requestId("metadata"),
			method: "pane.report_metadata",
			params: {
				pane_id: process.env.SAFE_PI_HERDR_PANE_ID,
				source: SOURCE,
				agent: AGENT,
				display_agent: DISPLAY_AGENT,
				seq: nextReportSeq(),
			},
		});
	}

	/**
	 * Clear the pane's agent attribution — its name, state, and stored resume
	 * command — because the sandboxed Pi is quitting. Sent only on a real quit,
	 * never on a session replacement, and awaited with a short deadline so
	 * `process.exit(0)` cannot drop it.
	 */
	async function release(): Promise<void> {
		await sendRequestAndWait(
			{
				id: requestId("release"),
				method: "pane.release_agent",
				params: {
					pane_id: process.env.SAFE_PI_HERDR_PANE_ID,
					source: SOURCE,
					agent: AGENT,
					seq: nextReportSeq(),
				},
			},
			RELEASE_TIMEOUT_MS,
		);
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
			reportMetadata();
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

	pi.on("session_shutdown", async (event) => {
		try {
			// Only a real quit releases the pane. A session replacement
			// (resume/new/fork) and an extension reload keep it, and the new
			// session reports instead.
			if (!rootSession || event?.reason !== "quit") {
				return;
			}
			rootSession = false;
			await release();
		} catch {
			// Best effort: a failed release never breaks a quit.
		}
	});
}
