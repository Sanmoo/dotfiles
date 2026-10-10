import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import herdrReporter from "../../../safe-pi/herdr-reporter";

type Handler = (event: unknown, ctx: unknown) => unknown;
type BlockedHandler = (data: { active?: boolean; label?: string } | undefined) => void;
type Request = { id?: string; method?: string; params?: Record<string, unknown> };

const SESSION_FILE = "/run/safe-pi/sessions/--repo--/2026-01-01T00-00-00.jsonl";
const PANE_ID = "w1:p1";
const HERDR_VARS = ["SAFE_PI_HERDR_ENV", "SAFE_PI_HERDR_SOCKET_PATH", "SAFE_PI_HERDR_PANE_ID"] as const;

const cleanups: Array<() => Promise<void>> = [];
const savedEnv = new Map<string, string | undefined>();

beforeEach(() => {
	for (const name of HERDR_VARS) {
		savedEnv.set(name, process.env[name]);
		delete process.env[name];
	}
});

afterEach(async () => {
	while (cleanups.length > 0) {
		await cleanups.pop()!();
	}
	for (const [name, value] of savedEnv) {
		if (value === undefined) {
			delete process.env[name];
		} else {
			process.env[name] = value;
		}
	}
	savedEnv.clear();
});

function setHerdrEnv(socketPath: string): void {
	process.env.SAFE_PI_HERDR_SOCKET_PATH = socketPath;
	process.env.SAFE_PI_HERDR_PANE_ID = PANE_ID;
}

function makeContext(overrides: Record<string, unknown> = {}) {
	return {
		mode: "tui",
		isIdle: () => true,
		sessionManager: {
			getSessionFile: () => SESSION_FILE,
			getSessionId: () => "session-id",
		},
		...overrides,
	};
}

function setupPi() {
	const handlers = new Map<string, Handler>();
	const blocked: BlockedHandler[] = [];
	const pi = {
		events: {
			on(_name: string, handler: BlockedHandler) {
				blocked.push(handler);
			},
		},
		on(name: string, handler: Handler) {
			handlers.set(name, handler);
		},
	};
	herdrReporter(pi as never);
	return { handlers, blocked };
}

async function startServer(): Promise<{
	socketPath: string;
	requests: Request[];
	stop: () => Promise<void>;
}> {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), "herdr-reporter-"));
	const socketPath = path.join(dir, "herdr.sock");
	const requests: Request[] = [];

	const server = net.createServer((connection) => {
		let buffer = "";
		connection.on("data", (chunk) => {
			buffer += chunk.toString();
			let index = buffer.indexOf("\n");
			while (index >= 0) {
				const line = buffer.slice(0, index);
				buffer = buffer.slice(index + 1);
				if (line.trim()) {
					requests.push(JSON.parse(line) as Request);
				}
				index = buffer.indexOf("\n");
			}
			// Acknowledge so the reporter closes the connection right away.
			connection.write("{}\n");
		});
	});

	await new Promise<void>((resolve, reject) => {
		server.once("error", reject);
		server.listen(socketPath, () => resolve());
	});

	return {
		socketPath,
		requests,
		stop: async () => {
			await new Promise<void>((resolve) => server.close(() => resolve()));
			fs.rmSync(dir, { recursive: true, force: true });
		},
	};
}

async function waitForRequests(requests: unknown[], count: number, timeoutMs = 1000): Promise<void> {
	await waitFor(() => requests.length >= count, `${count} requests`, timeoutMs);
}

async function waitFor(predicate: () => boolean, what: string, timeoutMs = 1000): Promise<void> {
	const start = Date.now();
	while (!predicate()) {
		if (Date.now() - start > timeoutMs) {
			throw new Error(`timed out waiting for ${what}`);
		}
		await new Promise((resolve) => setTimeout(resolve, 5));
	}
}

function statesOf(requests: Request[]): unknown[] {
	return requests.filter((request) => request.method === "pane.report_agent").map((request) => request.params?.state);
}

/** The reports that carry a resume command; a metadata report does not. */
function reportRequests(requests: Request[]): Request[] {
	return requests.filter((request) => request.method !== "pane.report_metadata");
}

describe("herdr-reporter", () => {
	it("stays inert outside a Herdr pane", () => {
		const { handlers, blocked } = setupPi();

		expect(handlers.size).toBe(0);
		expect(blocked).toEqual([]);
	});

	it("reports idle and the container-only session path at session start", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!({ reason: "startup" }, makeContext());
		await waitForRequests(requests, 3);

		const session = requests.find((request) => request.method === "pane.report_agent_session");
		const state = requests.find((request) => request.method === "pane.report_agent");
		const metadata = requests.find((request) => request.method === "pane.report_metadata");
		expect(session?.params).toMatchObject({
			source: "safe-pi",
			agent: "safe-pi",
			pane_id: PANE_ID,
			agent_session_path: SESSION_FILE,
			resume_argv: ["safe-pi", "--session", "session-id"],
			session_start_source: "startup",
		});
		expect(state?.params).toMatchObject({
			source: "safe-pi",
			agent: "safe-pi",
			pane_id: PANE_ID,
			state: "idle",
			agent_session_path: SESSION_FILE,
			resume_argv: ["safe-pi", "--session", "session-id"],
		});
		// The agent label is one Herdr does not recognize by process, so its
		// idle-shell safety net stays armed; display_agent keeps the visible name.
		expect(metadata?.params).toMatchObject({
			source: "safe-pi",
			agent: "safe-pi",
			pane_id: PANE_ID,
			display_agent: "Pi",
		});
	});

	it("carries a resume command Herdr will accept on every report", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers, blocked } = setupPi();

		await handlers.get("session_start")!({}, makeContext({ isIdle: () => false }));
		blocked[0]({ active: true, label: "Aguardando permissão" });
		await waitForRequests(requests, 3);

		for (const request of reportRequests(requests)) {
			const argv = request.params?.resume_argv as string[] | undefined;
			expect(Array.isArray(argv)).toBe(true);
			expect(argv![0]).toBe("safe-pi");
			expect(argv![0]).not.toContain("/");
			expect(argv!.length).toBeLessThanOrEqual(64);
			expect(argv!.reduce((bytes, arg) => bytes + arg.length, 0)).toBeLessThanOrEqual(8 * 1024);
			for (const arg of argv!) {
				expect(arg).not.toMatch(/['\u0000-\u001f\u007f]/);
			}
		}
	});

	it("re-states the resume command when the session changes", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!({}, makeContext());
		await waitForRequests(requests, 2);
		requests.length = 0;

		const otherSession = "/run/safe-pi/sessions/--repo--/2026-01-02T00-00-00.jsonl";
		await handlers.get("agent_start")!(
			{},
			makeContext({
				sessionManager: { getSessionFile: () => otherSession, getSessionId: () => "other-id" },
			}),
		);
		await waitForRequests(requests, 2);

		const session = requests.find((request) => request.method === "pane.report_agent_session");
		expect(session?.params).toMatchObject({
			agent_session_path: otherSession,
			resume_argv: ["safe-pi", "--session", "other-id"],
		});
	});

	it("names the exact session so a restart cannot reopen another one in the directory", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!(
			{},
			makeContext({
				sessionManager: {
					getSessionFile: () => SESSION_FILE,
					getSessionId: () => "019e20f0-6c1b-7b3d-9a5e-2f4c8d7e1a90",
				},
			}),
		);
		await waitForRequests(requests, 2);

		for (const request of reportRequests(requests)) {
			expect(request.params?.resume_argv).toEqual([
				"safe-pi",
				"--session",
				"019e20f0-6c1b-7b3d-9a5e-2f4c8d7e1a90",
			]);
		}
	});

	it("falls back to the most recent conversation when Pi reports no session id", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!(
			{},
			makeContext({
				sessionManager: { getSessionFile: () => SESSION_FILE, getSessionId: () => undefined },
			}),
		);
		await waitForRequests(requests, 2);

		const state = requests.find((request) => request.method === "pane.report_agent");
		expect(state?.params?.resume_argv).toEqual(["safe-pi", "-c"]);
	});

	it("refuses a reported id that is not a plain token", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!(
			{},
			makeContext({
				sessionManager: {
					getSessionFile: () => undefined,
					getSessionId: () => "-c && rm -rf /",
				},
			}),
		);
		await waitFor(() => statesOf(requests).length >= 1, "idle state");

		// The id reaches neither the resume command nor the stored session
		// reference: one rule governs both.
		expect(requests.some((request) => request.method === "pane.report_agent_session")).toBe(false);
		const state = requests.find((request) => request.method === "pane.report_agent");
		expect(state?.params?.agent_session_id).toBeUndefined();
		expect(state?.params?.resume_argv).toEqual(["safe-pi", "-c"]);
	});

	it("reports working during a turn and idle once it settles", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!({}, makeContext());
		await waitForRequests(requests, 2);
		await handlers.get("agent_start")!({}, makeContext({ isIdle: () => false }));
		await waitFor(() => statesOf(requests).length >= 2, "working state");
		await handlers.get("agent_settled")!({}, makeContext({ isIdle: () => true }));
		await waitFor(() => statesOf(requests).length >= 3, "settled state");

		expect(statesOf(requests)).toEqual(["idle", "working", "idle"]);
	});

	it("reports blocked while the approval gate is open and clears it", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers, blocked } = setupPi();

		await handlers.get("session_start")!({}, makeContext({ isIdle: () => false }));
		await waitFor(() => statesOf(requests).length >= 1, "working state");
		blocked[0]({ active: true, label: "Aguardando permissão" });
		await waitFor(() => statesOf(requests).length >= 2, "blocked state");
		blocked[0]({ active: false });
		await waitFor(() => statesOf(requests).length >= 3, "cleared state");

		expect(statesOf(requests)).toEqual(["working", "blocked", "working"]);
		const blockedRequest = requests.find((request) => request.params?.state === "blocked");
		expect(blockedRequest?.params?.message).toBe("Aguardando permissão");
	});

	it("does not re-report a state that has not changed", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!({}, makeContext());
		await waitForRequests(requests, 2);
		requests.length = 0;
		await handlers.get("agent_start")!({}, makeContext());
		await waitFor(() => statesOf(requests).length >= 1, "working state");
		requests.length = 0;
		await handlers.get("agent_start")!({}, makeContext());
		await new Promise((resolve) => setTimeout(resolve, 50));

		expect(statesOf(requests)).toEqual([]);
	});

	it("ignores headless sessions that Herdr could not display", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!({}, makeContext({ mode: "json" }));
		await handlers.get("agent_start")!({}, makeContext());
		await new Promise((resolve) => setTimeout(resolve, 50));

		expect(requests).toEqual([]);
	});

	it("ignores a session reference that is not an absolute path", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!(
			{},
			makeContext({
				sessionManager: { getSessionFile: () => "relative.jsonl", getSessionId: () => undefined },
			}),
		);
		await waitFor(() => statesOf(requests).length >= 1, "idle state");

		expect(requests.some((request) => request.method === "pane.report_agent_session")).toBe(false);
		expect(statesOf(requests)).toEqual(["idle"]);
		expect(requests[0]?.params?.agent_session_path).toBeUndefined();
	});

	it("releases the pane when the user quits", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!({}, makeContext());
		await waitForRequests(requests, 3);
		requests.length = 0;

		// Awaiting the handler must mean the release has been delivered: Pi calls
		// process.exit(0) the moment it resolves, so a fire-and-forget report here
		// would never leave the process.
		await handlers.get("session_shutdown")!({ reason: "quit" }, makeContext());

		const release = requests.find((request) => request.method === "pane.release_agent");
		expect(release?.params).toMatchObject({
			source: "safe-pi",
			agent: "safe-pi",
			pane_id: PANE_ID,
		});
		expect(typeof release?.params?.seq).toBe("number");
	});

	it("keeps the pane on a session replacement or a reload", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!({}, makeContext());
		await waitForRequests(requests, 3);

		for (const reason of ["reload", "resume", "new", "fork"]) {
			requests.length = 0;
			await handlers.get("session_shutdown")!({ reason }, makeContext());
			expect(requests.some((request) => request.method === "pane.release_agent")).toBe(false);
		}
	});

	it("does not release a headless session that Herdr could not display", async () => {
		const { socketPath, requests, stop } = await startServer();
		cleanups.push(stop);
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!({}, makeContext({ mode: "json" }));
		await handlers.get("session_shutdown")!({ reason: "quit" }, makeContext({ mode: "json" }));
		await new Promise((resolve) => setTimeout(resolve, 50));

		expect(requests).toEqual([]);
	});

	it("gives up on the release when Herdr accepts but never answers", async () => {
		const dir = fs.mkdtempSync(path.join(os.tmpdir(), "herdr-silent-"));
		const socketPath = path.join(dir, "herdr.sock");
		const accepted = new Set<net.Socket>();
		const server = net.createServer((socket) => {
			// Accept and stay silent: the reporter must stop waiting on its own.
			accepted.add(socket);
			socket.on("close", () => accepted.delete(socket));
		});
		await new Promise<void>((resolve, reject) => {
			server.once("error", reject);
			server.listen(socketPath, () => resolve());
		});
		cleanups.push(async () => {
			// server.close() waits for accepted connections to end; this server
			// never ends them, so destroy them first or the cleanup hangs.
			for (const socket of accepted) socket.destroy();
			await new Promise<void>((resolve) => server.close(() => resolve()));
			fs.rmSync(dir, { recursive: true, force: true });
		});
		setHerdrEnv(socketPath);
		const { handlers } = setupPi();

		await handlers.get("session_start")!({}, makeContext());

		const start = Date.now();
		await handlers.get("session_shutdown")!({ reason: "quit" }, makeContext());
		const elapsed = Date.now() - start;

		expect(elapsed).toBeGreaterThanOrEqual(200);
		// The cap is 250 ms; the upper bound must stay well under it so a
		// regression to a longer deadline fails this test.
		expect(elapsed).toBeLessThan(400);
	});

	it("never throws or slows Pi when the socket is unreachable", () => {
		process.env.SAFE_PI_HERDR_SOCKET_PATH = path.join(os.tmpdir(), `herdr-missing-${process.pid}.sock`);
		process.env.SAFE_PI_HERDR_PANE_ID = PANE_ID;
		const { handlers, blocked } = setupPi();

		const start = Date.now();
		expect(() => {
			handlers.get("session_start")!({}, makeContext());
			handlers.get("agent_start")!({}, makeContext());
			blocked[0]({ active: true, label: "x" });
			handlers.get("agent_settled")!({}, makeContext());
		}).not.toThrow();
		expect(Date.now() - start).toBeLessThan(200);
	});
});
