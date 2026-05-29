# Herdr UI Blocked Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local Pi extension that marks Herdr agent state as blocked while explicit Pi UI dialogs wait for user input, and load it first on Linux and macOS.

**Architecture:** Create a focused bridge extension at `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts`. The extension idempotently wraps explicit `ctx.ui` dialog methods and emits the existing `herdr:blocked` event before and after each dialog. Update platform settings so the bridge loads before local extensions that may show dialogs.

**Tech Stack:** Pi TypeScript extensions, Node/Bun tests with `bun:test`, JSON settings files.

---

## File Structure

- Create `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts`
  - Exports the Pi extension.
  - Exports small pure/testable helpers: `BLOCKED_LABEL`, `DIALOG_METHODS`, `wrapUiForHerdrBlocked`, and the marker symbol if useful for tests.
  - Does not import Herdr APIs or edit managed Herdr files.

- Create `pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts`
  - Tests wrapping behavior using a fake `pi.events.emit` and fake `ui` object.
  - Tests that explicit dialogs emit active true/false, preserve return values, preserve thrown errors, and do not wrap `custom`.

- Modify `pi-linux/.pi/agent/settings.json`
  - Add `~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts` as the first `extensions` entry.

- Modify `pi-mac/.pi/agent/settings.json`
  - Add `~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts` as the first `extensions` entry.

---

### Task 1: Add failing unit tests for the bridge wrapper

**Files:**
- Create: `pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts`

- [ ] **Step 1: Create the failing test file**

Write `pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts` with this content:

```ts
import { describe, expect, it } from "bun:test";
import {
	BLOCKED_LABEL,
	DIALOG_METHODS,
	wrapUiForHerdrBlocked,
} from "../../.pi/agent/extensions/00-herdr-ui-blocked-bridge";

type EmittedEvent = {
	name: string;
	data: unknown;
};

function createFakePi() {
	const events: EmittedEvent[] = [];
	return {
		events,
		pi: {
			events: {
				emit(name: string, data: unknown) {
					events.push({ name, data });
				},
			},
		},
	};
}

describe("herdr-ui-blocked-bridge", () => {
	it("wraps explicit dialog methods and preserves their return values", async () => {
		const { pi, events } = createFakePi();
		const ui = {
			async select(label: string, choices: string[]) {
				return `${label}:${choices[0]}`;
			},
		};

		wrapUiForHerdrBlocked(pi, ui);

		const result = await ui.select("Pick", ["A", "B"]);

		expect(result).toBe("Pick:A");
		expect(events).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: BLOCKED_LABEL },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("emits inactive when the original dialog throws and preserves the error", async () => {
		const { pi, events } = createFakePi();
		const expectedError = new Error("dialog failed");
		const ui = {
			async confirm() {
				throw expectedError;
			},
		};

		wrapUiForHerdrBlocked(pi, ui);

		await expect(ui.confirm()).rejects.toBe(expectedError);
		expect(events).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: BLOCKED_LABEL },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("is idempotent when the same ui object is wrapped more than once", async () => {
		const { pi, events } = createFakePi();
		const ui = {
			async input() {
				return "typed value";
			},
		};

		wrapUiForHerdrBlocked(pi, ui);
		wrapUiForHerdrBlocked(pi, ui);

		const result = await ui.input();

		expect(result).toBe("typed value");
		expect(events).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: BLOCKED_LABEL },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("wraps only explicit dialog methods and does not wrap custom", async () => {
		const { pi, events } = createFakePi();
		const ui = {
			async custom() {
				return "custom result";
			},
		};

		wrapUiForHerdrBlocked(pi, ui);

		const result = await ui.custom();

		expect(result).toBe("custom result");
		expect(events).toEqual([]);
		expect(DIALOG_METHODS).not.toContain("custom");
	});

	it("ignores emit failures without changing dialog behavior", async () => {
		const pi = {
			events: {
				emit() {
					throw new Error("no listeners available");
				},
			},
		};
		const ui = {
			async editor() {
				return "edited text";
			},
		};

		wrapUiForHerdrBlocked(pi, ui);

		await expect(ui.editor()).resolves.toBe("edited text");
	});
});
```

- [ ] **Step 2: Run the new test and verify it fails**

Run:

```bash
bun test pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts
```

Expected: FAIL because `../../.pi/agent/extensions/00-herdr-ui-blocked-bridge` does not exist yet.

- [ ] **Step 3: Commit the failing tests**

Run:

```bash
git add pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts
git commit -m "test: specify herdr ui blocked bridge"
```

---

### Task 2: Implement the Herdr UI blocked bridge extension

**Files:**
- Create: `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts`
- Test: `pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts`

- [ ] **Step 1: Create the extension implementation**

Write `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts` with this content:

```ts
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const BLOCKED_LABEL = "Aguardando input";
export const DIALOG_METHODS = ["select", "confirm", "input", "editor"] as const;

const wrappedMarker = Symbol("herdr-ui-blocked-bridge.wrapped");

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
			pi.events?.emit?.("herdr:blocked", { active: true, label: BLOCKED_LABEL });
			return;
		}

		pi.events?.emit?.("herdr:blocked", { active: false });
	} catch {
		// Herdr signaling must never break the original Pi dialog behavior.
	}
}

function wrapDialogMethod(pi: PiLike, ui: UiLike, methodName: DialogMethodName): void {
	const original = ui[methodName];
	if (typeof original !== "function") {
		return;
	}

	ui[methodName] = async function wrappedDialog(this: unknown, ...args: unknown[]) {
		safeEmitBlocked(pi, true);
		try {
			return await original.apply(this, args);
		} finally {
			safeEmitBlocked(pi, false);
		}
	};
}

export function wrapUiForHerdrBlocked(pi: PiLike, ui: unknown): void {
	if (!ui || typeof ui !== "object") {
		return;
	}

	const uiObject = ui as UiLike;
	if (uiObject[wrappedMarker]) {
		return;
	}

	for (const methodName of DIALOG_METHODS) {
		wrapDialogMethod(pi, uiObject, methodName);
	}

	uiObject[wrappedMarker] = true;
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
```

- [ ] **Step 2: Run the focused unit test and verify it passes**

Run:

```bash
bun test pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts
```

Expected: PASS for all tests in `herdr-ui-blocked-bridge.test.ts`.

- [ ] **Step 3: Run existing Pi agent tests**

Run:

```bash
bun test pi/tests/pi-agent
```

Expected: PASS for `pi-auto-rename.test.ts` and `herdr-ui-blocked-bridge.test.ts`.

- [ ] **Step 4: Commit the implementation**

Run:

```bash
git add pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts
git commit -m "feat: bridge pi ui dialogs to herdr blocked state"
```

---

### Task 3: Load the bridge first on Linux and macOS

**Files:**
- Modify: `pi-linux/.pi/agent/settings.json`
- Modify: `pi-mac/.pi/agent/settings.json`

- [ ] **Step 1: Update Linux Pi settings**

Modify the `extensions` array in `pi-linux/.pi/agent/settings.json` so it becomes:

```json
  "extensions": [
    "~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts",
    "~/.pi/agent/extensions/herdr-subagent-guard.ts"
  ],
```

Do not change unrelated settings.

- [ ] **Step 2: Update macOS Pi settings**

Modify the `extensions` array in `pi-mac/.pi/agent/settings.json` so it becomes:

```json
  "extensions": [
    "~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts",
    "~/.pi/agent/extensions/herdr-subagent-guard.ts"
  ],
```

Do not change unrelated settings.

- [ ] **Step 3: Validate JSON syntax**

Run:

```bash
node -e 'for (const f of ["pi-linux/.pi/agent/settings.json", "pi-mac/.pi/agent/settings.json"]) { JSON.parse(require("node:fs").readFileSync(f, "utf8")); console.log(`${f}: ok`); }'
```

Expected output:

```text
pi-linux/.pi/agent/settings.json: ok
pi-mac/.pi/agent/settings.json: ok
```

- [ ] **Step 4: Verify the bridge is first in both settings files**

Run:

```bash
node - <<'NODE'
const fs = require('node:fs');
for (const file of ['pi-linux/.pi/agent/settings.json', 'pi-mac/.pi/agent/settings.json']) {
  const settings = JSON.parse(fs.readFileSync(file, 'utf8'));
  const first = settings.extensions?.[0];
  if (first !== '~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts') {
    throw new Error(`${file}: first extension is ${first}`);
  }
  console.log(`${file}: bridge first`);
}
NODE
```

Expected output:

```text
pi-linux/.pi/agent/settings.json: bridge first
pi-mac/.pi/agent/settings.json: bridge first
```

- [ ] **Step 5: Commit settings changes**

Run:

```bash
git add pi-linux/.pi/agent/settings.json pi-mac/.pi/agent/settings.json
git commit -m "config: load herdr ui blocked bridge first"
```

---

### Task 4: Final verification and manual test notes

**Files:**
- Read: `docs/superpowers/specs/2026-05-28-herdr-ui-blocked-bridge-design.md`
- Verify: `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts`
- Verify: `pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts`
- Verify: `pi-linux/.pi/agent/settings.json`
- Verify: `pi-mac/.pi/agent/settings.json`

- [ ] **Step 1: Run focused and existing tests**

Run:

```bash
bun test pi/tests/pi-agent
```

Expected: PASS for all tests in `pi/tests/pi-agent`.

- [ ] **Step 2: Re-validate settings JSON and ordering**

Run:

```bash
node - <<'NODE'
const fs = require('node:fs');
for (const file of ['pi-linux/.pi/agent/settings.json', 'pi-mac/.pi/agent/settings.json']) {
  const settings = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (settings.extensions?.[0] !== '~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts') {
    throw new Error(`${file}: bridge is not first`);
  }
  if (!settings.extensions.includes('~/.pi/agent/extensions/herdr-subagent-guard.ts')) {
    throw new Error(`${file}: herdr-subagent-guard missing`);
  }
  console.log(`${file}: ok`);
}
NODE
```

Expected output:

```text
pi-linux/.pi/agent/settings.json: ok
pi-mac/.pi/agent/settings.json: ok
```

- [ ] **Step 3: Confirm no managed Herdr integration file is modified**

Run:

```bash
git status --short /home/sanmoo/.pi/agent/extensions/herdr-agent-state.ts || true
git status --short
```

Expected: no tracked change for `/home/sanmoo/.pi/agent/extensions/herdr-agent-state.ts`. The repository status may show pre-existing unrelated changes, but this feature's tracked changes should only be the new extension, new test, and two platform settings files.

- [ ] **Step 4: Document manual validation for the user**

In the final implementation response, include these manual validation steps:

```text
Inside Herdr:
1. Reload/restart Pi so the new extension is loaded.
2. Trigger a permission-gate dialog, for example by asking Pi to run a sudo or rm -rf command that opens ctx.ui.select.
3. While the dialog is visible, confirm Herdr marks the agent blocked with label "Aguardando input".
4. Answer or cancel the dialog.
5. Confirm Herdr leaves blocked state.

Outside Herdr:
1. Start Pi outside a Herdr pane.
2. Trigger a select/confirm/input/editor dialog.
3. Confirm the dialog works normally and no Herdr-related error appears.
```

- [ ] **Step 5: Commit any final verification-only adjustments**

If final verification required code or config edits, run:

```bash
git add pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts pi-linux/.pi/agent/settings.json pi-mac/.pi/agent/settings.json
git commit -m "fix: finalize herdr ui blocked bridge"
```

If no edits were needed, do not create an empty commit.
