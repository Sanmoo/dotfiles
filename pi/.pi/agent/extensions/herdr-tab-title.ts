import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

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

export default function herdrTabTitle(_pi: ExtensionAPI) {
	// Task 1 only: event wiring arrives later.
}
