# Permission Gate Herdr Blocked Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `permission-gate.ts` directly report Herdr `blocked` status while waiting for dangerous-command permission input, then clear it after the user responds.

**Architecture:** Remove the generic UI bridge and make the permission gate own its Herdr status signaling. The gate emits `herdr:blocked` active immediately before `ctx.ui.select(...)`, clears it in `finally`, and keeps Herdr failures isolated from security behavior.

**Tech Stack:** TypeScript Pi extension API, Bun test runner, Pi extension event bus (`pi.events.emit`).

---

## File Structure

- Modify `pi/.pi/agent/extensions/permission-gate.ts`
  - One responsibility remains: guard dangerous bash commands.
  - Add a small Herdr event helper local to this file.
  - Add `try/finally` around the existing permission prompt.

- Create `pi/tests/pi-agent/permission-gate.test.ts`
  - Unit tests for direct permission-gate behavior.
  - Fake Pi extension API records the `tool_call` handler and emitted Herdr events.
  - Fake UI methods simulate allow, deny, throwing prompt, and event-emitter failures.

- Delete `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts`
  - Remove unused generic UI wrapper.

- Delete `pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts`
  - Remove tests for deleted bridge.

- Modify `pi-linux/.pi/agent/settings.json`
  - Remove `~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts` from `extensions`.

- Modify `pi-mac/.pi/agent/settings.json`
  - Remove `~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts` from `extensions`.

---

### Task 1: Add failing permission-gate tests

**Files:**
- Create: `pi/tests/pi-agent/permission-gate.test.ts`
- Read: `pi/.pi/agent/extensions/permission-gate.ts`

- [ ] **Step 1: Create the failing test file**

Create `pi/tests/pi-agent/permission-gate.test.ts` with this content:

```ts
import { describe, expect, it } from "bun:test";
import permissionGate from "../../.pi/agent/extensions/permission-gate";

type ToolCallHandler = (event: {
	toolName: string;
	input: { command?: string };
}, ctx: {
	hasUI: boolean;
	ui: {
		select: (message: string, choices: string[]) => Promise<string | undefined>;
	};
}) => Promise<unknown> | unknown;

type EmittedEvent = {
	name: string;
	data: unknown;
};

function setupPermissionGate(options?: { emitThrows?: boolean }) {
	let handler: ToolCallHandler | undefined;
	const emitted: EmittedEvent[] = [];

	const pi = {
		events: {
			emit(name: string, data: unknown) {
				if (options?.emitThrows) {
					throw new Error("emit failed");
				}
				emitted.push({ name, data });
			},
		},
		on(name: string, callback: ToolCallHandler) {
			expect(name).toBe("tool_call");
			handler = callback;
		},
	};

	permissionGate(pi as never);

	if (!handler) {
		throw new Error("permission gate did not register a tool_call handler");
	}

	return { handler, emitted };
}

function bashEvent(command: string) {
	return {
		toolName: "bash",
		input: { command },
	};
}

function uiContext(select: (message: string, choices: string[]) => Promise<string | undefined>) {
	return {
		hasUI: true,
		ui: { select },
	};
}

describe("permission-gate", () => {
	it("does not block safe bash commands or emit Herdr blocked events", async () => {
		const { handler, emitted } = setupPermissionGate();

		const result = await handler(
			bashEvent("echo hello"),
			uiContext(async () => {
				throw new Error("select should not be called for safe commands");
			}),
		);

		expect(result).toBeUndefined();
		expect(emitted).toEqual([]);
	});

	it("emits Herdr blocked while waiting for permission and allows when user selects Sim", async () => {
		const { handler, emitted } = setupPermissionGate();
		const promptEvents: string[] = [];

		const result = await handler(
			bashEvent("sudo id"),
			uiContext(async (message, choices) => {
				promptEvents.push(message);
				expect(choices).toEqual(["Sim", "Não"]);
				expect(emitted).toEqual([
					{
						name: "herdr:blocked",
						data: { active: true, label: "Aguardando permissão" },
					},
				]);
				return "Sim";
			}),
		);

		expect(result).toBeUndefined();
		expect(promptEvents).toHaveLength(1);
		expect(promptEvents[0]).toContain("sudo id");
		expect(emitted).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: "Aguardando permissão" },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("clears Herdr blocked and blocks command when user selects Não", async () => {
		const { handler, emitted } = setupPermissionGate();

		const result = await handler(
			bashEvent("rm -rf build"),
			uiContext(async () => "Não"),
		);

		expect(result).toEqual({ block: true, reason: "Bloqueado pelo usuário" });
		expect(emitted).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: "Aguardando permissão" },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("clears Herdr blocked when permission prompt throws", async () => {
		const { handler, emitted } = setupPermissionGate();
		const expectedError = new Error("prompt failed");

		await expect(
			handler(
				bashEvent("sudo id"),
				uiContext(async () => {
					throw expectedError;
				}),
			),
		).rejects.toBe(expectedError);

		expect(emitted).toEqual([
			{
				name: "herdr:blocked",
				data: { active: true, label: "Aguardando permissão" },
			},
			{
				name: "herdr:blocked",
				data: { active: false },
			},
		]);
	});

	it("blocks dangerous commands without UI and emits no Herdr blocked events", async () => {
		const { handler, emitted } = setupPermissionGate();

		const result = await handler(bashEvent("sudo id"), {
			hasUI: false,
			ui: {
				select: async () => {
					throw new Error("select should not be called without UI");
				},
			},
		});

		expect(result).toEqual({
			block: true,
			reason: "Comando perigoso bloqueado (modo não interativo)",
		});
		expect(emitted).toEqual([]);
	});

	it("continues permission prompt behavior when Herdr event emission fails", async () => {
		const { handler, emitted } = setupPermissionGate({ emitThrows: true });

		const result = await handler(
			bashEvent("sudo id"),
			uiContext(async () => "Sim"),
		);

		expect(result).toBeUndefined();
		expect(emitted).toEqual([]);
	});
});
```

- [ ] **Step 2: Run the new tests to verify they fail before implementation**

Run:

```bash
bun test pi/tests/pi-agent/permission-gate.test.ts
```

Expected result:

- Tests involving Herdr events fail because `permission-gate.ts` does not emit `herdr:blocked` yet.
- The safe-command and non-interactive tests may already pass.

- [ ] **Step 3: Commit the failing tests**

Run:

```bash
git add pi/tests/pi-agent/permission-gate.test.ts
git commit -m "test: cover permission gate herdr blocked status"
```

---

### Task 2: Implement direct Herdr blocked signaling

**Files:**
- Modify: `pi/.pi/agent/extensions/permission-gate.ts`
- Test: `pi/tests/pi-agent/permission-gate.test.ts`

- [ ] **Step 1: Replace `permission-gate.ts` with direct Herdr signaling**

Replace the full contents of `pi/.pi/agent/extensions/permission-gate.ts` with:

```ts
/**
 * Permission Gate Extension
 *
 * Prompts for confirmation before running potentially dangerous bash commands.
 * Blocks by default in non-interactive mode (--print, --mode json, etc.).
 * Emits Herdr blocked status while waiting for interactive permission input.
 *
 * Patterns checked: rm -rf, sudo, chmod/chown 777, dd, fdisk, mkfs,
 * destructive redirects (>/dev/...), and pipe from curl/wget to shell.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const HERDR_BLOCKED_LABEL = "Aguardando permissão";

function emitHerdrBlocked(pi: ExtensionAPI, active: boolean): void {
	try {
		if (active) {
			pi.events.emit("herdr:blocked", {
				active: true,
				label: HERDR_BLOCKED_LABEL,
			});
			return;
		}

		pi.events.emit("herdr:blocked", { active: false });
	} catch {
		// Herdr signaling is best-effort and must never weaken permission gating.
	}
}

export default function (pi: ExtensionAPI) {
	const dangerousPatterns = [
		/\brm\s+(-rf?|--recursive)/i,
		/\bsudo\b/i,
		/\b(chmod|chown)\b.*777/i,
		/\bdd\b/i,
		/\bmkfs\./i,
		/\bfdisk\b/i,
		/\bparted\b/i,
		/>\s*\/dev\/(sd[a-z]|nvme[0-9]|vd[a-z]|mmcblk[0-9]|loop[0-9]|sr[0-9]|disk\/)/i,
		/\b(curl|wget)\b.*\|\s*(ba)?sh\b/i,
		/\b(>\|?)\s*\/etc\//i,
		/\bchattr\b/i,
	];

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		const isDangerous = dangerousPatterns.some((p) => p.test(command));

		if (isDangerous) {
			if (!ctx.hasUI) {
				return { block: true, reason: "Comando perigoso bloqueado (modo não interativo)" };
			}

			emitHerdrBlocked(pi, true);
			let choice: string | undefined;
			try {
				choice = await ctx.ui.select(
					`⚠️ Comando suspeito:\n\n  ${command}\n\nPermitir?`,
					["Sim", "Não"],
				);
			} finally {
				emitHerdrBlocked(pi, false);
			}

			if (choice !== "Sim") {
				return { block: true, reason: "Bloqueado pelo usuário" };
			}
		}

		return undefined;
	});
}
```

- [ ] **Step 2: Run the permission-gate tests**

Run:

```bash
bun test pi/tests/pi-agent/permission-gate.test.ts
```

Expected result:

```text
6 pass
0 fail
```

Bun may also print timing details; failure count must be zero.

- [ ] **Step 3: Commit implementation**

Run:

```bash
git add pi/.pi/agent/extensions/permission-gate.ts
git commit -m "feat: report herdr blocked during permission prompts"
```

---

### Task 3: Remove the generic Herdr UI bridge

**Files:**
- Delete: `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts`
- Delete: `pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts`
- Modify: `pi-linux/.pi/agent/settings.json`
- Modify: `pi-mac/.pi/agent/settings.json`

- [ ] **Step 1: Delete bridge files**

Run:

```bash
rm pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts
rm pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts
```

Expected result: both files are removed from the working tree.

- [ ] **Step 2: Remove bridge extension from Linux settings**

Edit `pi-linux/.pi/agent/settings.json` so this block:

```json
  "extensions": [
    "~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts"
  ],
```

becomes:

```json
  "extensions": [],
```

- [ ] **Step 3: Remove bridge extension from macOS settings**

Edit `pi-mac/.pi/agent/settings.json` so this block:

```json
  "extensions": [
    "~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts"
  ],
```

becomes:

```json
  "extensions": [],
```

- [ ] **Step 4: Verify no repository references to the removed bridge remain**

Run:

```bash
rg -n "00-herdr-ui-blocked-bridge|herdr-ui-blocked-bridge" pi pi-linux pi-mac
```

Expected result: no output and exit code `1` from `rg` because there are no matches.

- [ ] **Step 5: Commit bridge removal**

Run:

```bash
git add pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts \
  pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts \
  pi-linux/.pi/agent/settings.json \
  pi-mac/.pi/agent/settings.json
git commit -m "chore: remove herdr ui blocked bridge"
```

---

### Task 4: Final verification

**Files:**
- Test: `pi/tests/pi-agent/permission-gate.test.ts`
- Inspect: `pi/.pi/agent/extensions/permission-gate.ts`
- Inspect: `pi-linux/.pi/agent/settings.json`
- Inspect: `pi-mac/.pi/agent/settings.json`

- [ ] **Step 1: Run focused permission-gate tests**

Run:

```bash
bun test pi/tests/pi-agent/permission-gate.test.ts
```

Expected result:

```text
6 pass
0 fail
```

- [ ] **Step 2: Run all Pi agent tests present in the repository**

Run:

```bash
bun test pi/tests/pi-agent
```

Expected result: all remaining tests pass with `0 fail`.

- [ ] **Step 3: Verify removed bridge references do not remain**

Run:

```bash
rg -n "00-herdr-ui-blocked-bridge|herdr-ui-blocked-bridge" pi pi-linux pi-mac || true
```

Expected result: no matches printed.

- [ ] **Step 4: Verify no unintended files are staged or modified by this work**

Run:

```bash
git status --short
```

Expected result:

- Only pre-existing unrelated local changes may remain, such as `mise/.config/mise/config.toml`, `pi-linux/.pi/agent/settings.json` if it was dirty before the plan started, or untracked scratch files.
- No staged files after all commits.

- [ ] **Step 5: Manual Herdr validation**

Inside a Herdr-managed Pi pane, trigger a dangerous command permission prompt. One practical way is to ask Pi to run a command that matches the permission gate, such as `sudo id`, then observe Herdr while the prompt is open.

Expected behavior:

1. Herdr pane reports `blocked` while the permission prompt is waiting.
2. Selecting `Sim` clears `blocked` and allows the tool call.
3. Triggering another prompt and selecting `Não` clears `blocked` and blocks the tool call.
4. Pi does not remain stuck as `blocked` after either input.

- [ ] **Step 6: Commit any final verification-only adjustments**

If verification required no file changes, do not commit anything.

If a verification adjustment was needed, run:

```bash
git add pi/.pi/agent/extensions/permission-gate.ts \
  pi/tests/pi-agent/permission-gate.test.ts \
  pi-linux/.pi/agent/settings.json \
  pi-mac/.pi/agent/settings.json
git commit -m "fix: finalize permission gate herdr blocked status"
```

Expected result: either no commit is needed, or the final commit contains only verification-driven corrections for this feature.

---

## Self-Review Notes

- Spec coverage: the plan removes the bridge, removes its tests, removes settings references, adds direct `herdr:blocked` emission, clears in `finally`, preserves non-interactive blocking, and adds automated plus manual validation.
- Placeholder scan: no deferred implementation placeholders are present; code and commands are explicit.
- Type consistency: tests use a fake `tool_call` handler matching the current extension shape; implementation uses `ExtensionAPI`, `pi.events.emit`, `ctx.hasUI`, and `ctx.ui.select` consistently.
