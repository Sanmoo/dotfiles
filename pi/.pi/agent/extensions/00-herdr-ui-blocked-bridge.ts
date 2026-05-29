import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const BLOCKED_LABEL = "Aguardando input";
export const DIALOG_METHODS = ["select", "confirm", "input", "editor"] as const;

const wrappedMarker = Symbol.for("herdr-ui-blocked-bridge.wrapped");
const uiWrappedMarker = Symbol.for("herdr-ui-blocked-bridge.ui-wrapped");

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

function isWrappedFunction(value: unknown): boolean {
	if (typeof value !== "function") {
		return false;
	}

	try {
		return Boolean(value[wrappedMarker]);
	} catch {
		return false;
	}
}

function wrapDialogMethod(
	pi: PiLike,
	ui: UiLike,
	methodName: DialogMethodName,
): boolean {
	let original: unknown;
	try {
		original = ui[methodName];
	} catch {
		return false;
	}

	if (isWrappedFunction(original)) {
		return true;
	}

	if (typeof original !== "function") {
		return false;
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
		return true;
	} catch {
		// Wrapping is best-effort: frozen/sealed/proxy UI objects must remain fail-open.
		return false;
	}
}

export function wrapUiForHerdrBlocked(pi: PiLike, ui: unknown): void {
	if (!ui || typeof ui !== "object") {
		return;
	}

	const uiObject = ui as UiLike;
	try {
		if (uiObject[uiWrappedMarker]) {
			return;
		}
	} catch {
		// Marker checks are best-effort: proxies/accessors must remain fail-open.
	}

	let hasWrappedOrAlreadyWrappedDialog = false;
	for (const methodName of DIALOG_METHODS) {
		hasWrappedOrAlreadyWrappedDialog =
			wrapDialogMethod(pi, uiObject, methodName) ||
			hasWrappedOrAlreadyWrappedDialog;
	}

	if (!hasWrappedOrAlreadyWrappedDialog) {
		return;
	}

	try {
		Object.defineProperty(uiObject, uiWrappedMarker, { value: true });
	} catch {
		// Marking is best-effort: frozen/sealed/proxy UI objects must remain fail-open.
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
