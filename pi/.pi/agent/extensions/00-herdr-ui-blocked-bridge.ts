import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const BLOCKED_LABEL = "Aguardando input";
export const DIALOG_METHODS = ["select", "confirm", "input", "editor"] as const;

const wrappedMarker = Symbol.for("herdr-ui-blocked-bridge.wrapped");

type DialogMethodName = (typeof DIALOG_METHODS)[number];
type UiLike = Record<string | symbol, unknown>;
type PiLike = {
	events?: {
		emit?: (name: string, data: unknown) => unknown;
	};
};

function safeEmitBlocked(pi: PiLike, active: boolean): void {
	try {
		if (active) {
			pi.events?.emit?.("herdr:blocked", {
				active: true,
				label: BLOCKED_LABEL,
			});
			return;
		}

		pi.events?.emit?.("herdr:blocked", { active: false });
	} catch {
		// Herdr signaling must never break the original Pi dialog behavior.
	}
}

function wrapDialogMethod(
	pi: PiLike,
	ui: UiLike,
	methodName: DialogMethodName,
): void {
	let original: unknown;
	try {
		original = ui[methodName];
	} catch {
		return;
	}

	if (typeof original !== "function" || original[wrappedMarker]) {
		return;
	}

	const wrappedDialog = async function wrappedDialog(
		this: unknown,
		...args: unknown[]
	) {
		safeEmitBlocked(pi, true);
		try {
			return await original.apply(this, args);
		} finally {
			safeEmitBlocked(pi, false);
		}
	};

	Object.defineProperty(wrappedDialog, wrappedMarker, { value: true });

	try {
		ui[methodName] = wrappedDialog;
	} catch {
		// Wrapping is best-effort: frozen/sealed/proxy UI objects must remain fail-open.
	}
}

export function wrapUiForHerdrBlocked(pi: PiLike, ui: unknown): void {
	if (!ui || typeof ui !== "object") {
		return;
	}

	const uiObject = ui as UiLike;
	for (const methodName of DIALOG_METHODS) {
		wrapDialogMethod(pi, uiObject, methodName);
	}
}

export default function (pi: ExtensionAPI) {
	function wrapContextUi(ctx: unknown): void {
		const ui = (ctx as { ui?: unknown } | undefined)?.ui;
		wrapUiForHerdrBlocked(pi, ui);
	}

	pi.on("session_start", (_event, ctx) => wrapContextUi(ctx));
	pi.on("before_agent_start", (_event, ctx) => wrapContextUi(ctx));
	pi.on("agent_start", (_event, ctx) => wrapContextUi(ctx));
	pi.on("tool_call", (_event, ctx) => wrapContextUi(ctx));
}
