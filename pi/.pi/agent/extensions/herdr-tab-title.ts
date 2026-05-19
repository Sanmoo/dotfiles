import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";

export function buildSessionTitle(
	sessionName: string | null | undefined,
): string | null {
	const name = sessionName?.trim();
	return name ? `pi: ${name}` : null;
}

export function chooseTabLabel(
	sessionName: string | null | undefined,
	originalTabLabel: string | null | undefined,
): string | null {
	const original = originalTabLabel?.trim();
	return buildSessionTitle(sessionName) ?? (original ? original : null);
}

export function parsePaneTabId(stdout: string): string | null {
	try {
		const parsed = JSON.parse(stdout);
		return parsed?.result?.pane?.tab_id ?? null;
	} catch {
		return null;
	}
}

export function parseTabLabel(stdout: string): string | null {
	try {
		const parsed = JSON.parse(stdout);
		const label = parsed?.result?.tab?.label;
		return typeof label === "string" && label.trim() ? label : null;
	} catch {
		return null;
	}
}

export type HerdrCommandRunner = {
	runJson(args: string[]): Promise<string | null>;
	run(args: string[]): Promise<boolean>;
};

export type HerdrTabTitleController = {
	initialize(sessionName: string | null | undefined): Promise<void>;
	sync(sessionName: string | null | undefined): Promise<void>;
	shutdown(): Promise<void>;
	getState(): {
		enabled: boolean;
		tabId: string | null;
		originalTabLabel: string | null;
		lastAppliedLabel: string | null;
	};
};

function execHerdr(args: string[]): Promise<string | null> {
	return new Promise((resolve) => {
		execFile("herdr", args, { encoding: "utf8" }, (error, stdout) => {
			if (error) {
				resolve(null);
				return;
			}
			resolve(stdout);
		});
	});
}

export function createExecHerdrRunner(): HerdrCommandRunner {
	return {
		async runJson(args) {
			return execHerdr(args);
		},
		async run(args) {
			const stdout = await execHerdr(args);
			return stdout !== null;
		},
	};
}

export function createHerdrTabTitleController({
	env,
	runner,
}: {
	env: Record<string, string | undefined>;
	runner: HerdrCommandRunner;
}): HerdrTabTitleController {
	const enabled = env.HERDR_ENV === "1" && Boolean(env.HERDR_PANE_ID);
	let tabId: string | null = null;
	let originalTabLabel: string | null = null;
	let lastAppliedLabel: string | null = null;

	async function rename(label: string): Promise<void> {
		if (!tabId || label === lastAppliedLabel) {
			return;
		}

		const ok = await runner.run(["tab", "rename", tabId, label]);
		if (ok) {
			lastAppliedLabel = label;
		}
	}

	async function initialize(
		sessionName: string | null | undefined,
	): Promise<void> {
		if (!enabled || !env.HERDR_PANE_ID) {
			return;
		}

		const paneStdout = await runner.runJson(["pane", "get", env.HERDR_PANE_ID]);
		const resolvedTabId = paneStdout ? parsePaneTabId(paneStdout) : null;
		if (!resolvedTabId) {
			return;
		}

		tabId = resolvedTabId;

		const tabStdout = await runner.runJson(["tab", "get", tabId]);
		originalTabLabel = tabStdout ? parseTabLabel(tabStdout) : null;
		lastAppliedLabel = originalTabLabel;

		await sync(sessionName);
	}

	async function sync(sessionName: string | null | undefined): Promise<void> {
		if (!enabled || !tabId) {
			return;
		}

		const nextLabel = chooseTabLabel(sessionName, originalTabLabel);
		if (!nextLabel || nextLabel === lastAppliedLabel) {
			return;
		}

		await rename(nextLabel);
	}

	async function shutdown(): Promise<void> {
		if (!enabled || !tabId || !originalTabLabel) {
			return;
		}

		if (lastAppliedLabel === originalTabLabel) {
			return;
		}

		await rename(originalTabLabel);
	}

	return {
		initialize,
		sync,
		shutdown,
		getState() {
			return {
				enabled,
				tabId,
				originalTabLabel,
				lastAppliedLabel,
			};
		},
	};
}

export function registerHerdrTabTitle(
	pi: Pick<ExtensionAPI, "on" | "getSessionName">,
	controllerFactory: () => HerdrTabTitleController = () =>
		createHerdrTabTitleController({
			env: process.env,
			runner: createExecHerdrRunner(),
		}),
) {
	const controller = controllerFactory();

	pi.on("session_start", async () => {
		await controller.initialize(pi.getSessionName());
	});

	pi.on("turn_start", async () => {
		await controller.sync(pi.getSessionName());
	});

	pi.on("session_shutdown", async () => {
		await controller.shutdown();
	});

	return controller;
}

export default function herdrTabTitle(pi: ExtensionAPI) {
	registerHerdrTabTitle(pi);
}
