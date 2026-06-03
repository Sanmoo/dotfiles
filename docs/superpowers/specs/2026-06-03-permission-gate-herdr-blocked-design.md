# Permission Gate Herdr Blocked Status Design

**Date:** 2026-06-03
**Status:** Approved in brainstorming; awaiting user review of written spec
**Scope:** Update the local Pi permission gate extension so Herdr marks the pane as blocked while waiting for permission input, then returns to the correct non-blocked state after the user responds.

---

## 1. Problem Statement

The local Pi extension at `pi/.pi/agent/extensions/permission-gate.ts` prompts for confirmation before running dangerous bash commands. When Pi runs inside Herdr, this permission prompt should make the Herdr pane status become `blocked`, because Pi is waiting for user input.

The current behavior does not reliably update Herdr to `blocked`. A separate bridge extension, `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts`, attempted to wrap generic Pi UI dialog methods and emit `herdr:blocked`, but it has not been useful in practice and should be removed.

The permission gate should own its Herdr blocked signaling directly.

---

## 2. Goals and Non-Goals

### Goals

- Remove the unused `00-herdr-ui-blocked-bridge.ts` extension.
- Remove its test file.
- Remove settings references to the bridge extension.
- Update `permission-gate.ts` to emit Herdr blocked events directly around the permission prompt.
- Ensure Herdr leaves `blocked` after the user responds, whether the command is allowed, denied, cancelled, or the prompt throws.
- Keep non-interactive behavior unchanged: dangerous commands are blocked by default when no UI is available.

### Non-Goals

- Do not modify the Herdr-managed integration file `~/.pi/agent/extensions/herdr-agent-state.ts`.
- Do not create a replacement generic UI bridge.
- Do not change the dangerous-command pattern list unless needed for tests.
- Do not change Herdr's socket protocol or agent-state extension behavior.

---

## 3. Context and Evidence

Relevant files:

- `pi/.pi/agent/extensions/permission-gate.ts`
- `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts`
- `pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts`
- `~/.pi/agent/extensions/herdr-agent-state.ts`
- `~/.pi/agent/settings.json`
- `pi-linux/.pi/agent/settings.json`
- `pi-mac/.pi/agent/settings.json`

The Herdr-installed Pi integration listens on Pi's extension event bus:

- `pi.events.on("herdr:blocked", ...)`

It tracks a blocked count:

- `{ active: true, label }` increments blocked state
- `{ active: false }` decrements blocked state
- while blocked count is positive, reported agent state is `blocked`

Therefore, `permission-gate.ts` can integrate with Herdr without speaking directly to Herdr's socket. It only needs to emit the same extension-bus events.

---

## 4. Chosen Approach

Use direct, local signaling inside `permission-gate.ts`.

When a dangerous bash command is detected and Pi has UI available:

1. emit `herdr:blocked` active before showing the permission prompt
2. show the existing `ctx.ui.select(...)` prompt
3. emit `herdr:blocked` inactive in a `finally` block
4. block the command unless the user selected `"Sim"`

This keeps the behavior explicit, small, and tied to the only prompt that currently needs this status transition.

---

## 5. Detailed Behavior

### Interactive dangerous command

For a dangerous command such as `sudo id`:

1. `permission-gate.ts` matches the command.
2. Because `ctx.hasUI` is true, it emits:

   ```ts
   pi.events.emit("herdr:blocked", {
     active: true,
     label: "Aguardando permissão",
   });
   ```

3. It opens the existing select prompt.
4. Once the prompt resolves or rejects, it emits:

   ```ts
   pi.events.emit("herdr:blocked", { active: false });
   ```

5. If the user selected `"Sim"`, the command proceeds.
6. Otherwise, the command is blocked with reason `"Bloqueado pelo usuário"`.

### Prompt errors or cancellation

The inactive event must be emitted in `finally`, not after the prompt, so Herdr never remains stuck as `blocked` if the prompt fails or is cancelled.

### Non-interactive dangerous command

When `ctx.hasUI` is false:

- return the current non-interactive block response
- do not emit `herdr:blocked`, because Pi is not waiting for user input

### Safe commands

Safe commands remain unchanged and emit no Herdr events.

---

## 6. Implementation Shape

`permission-gate.ts` should include a small helper such as:

```ts
function emitHerdrBlocked(pi: ExtensionAPI, active: boolean, label?: string): void {
  try {
    if (active) {
      pi.events.emit("herdr:blocked", { active: true, label });
      return;
    }
    pi.events.emit("herdr:blocked", { active: false });
  } catch {
    // Herdr signaling must never break permission gating.
  }
}
```

The prompt block should use `try/finally`:

```ts
emitHerdrBlocked(pi, true, "Aguardando permissão");
try {
  choice = await ctx.ui.select(...);
} finally {
  emitHerdrBlocked(pi, false);
}
```

The exact helper name can vary. The important requirements are:

- fail open for Herdr signaling errors
- keep permission-gate behavior authoritative
- always clear `blocked` after user input or prompt failure

---

## 7. Files to Change

### Modify

- `pi/.pi/agent/extensions/permission-gate.ts`
  - add direct `herdr:blocked` emit logic
  - wrap the permission prompt in `try/finally`

- `pi-linux/.pi/agent/settings.json`
  - remove the explicit `~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts` reference

- `pi-mac/.pi/agent/settings.json`
  - remove the explicit `~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts` reference

### Remove

- `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts`
- `pi/tests/pi-agent/herdr-ui-blocked-bridge.test.ts`

### Add or Replace Tests

Add focused tests for `permission-gate.ts`, covering direct Herdr event emission and command blocking behavior.

Suggested test file:

- `pi/tests/pi-agent/permission-gate.test.ts`

---

## 8. Test Plan

Automated tests should cover:

1. Safe bash command emits no Herdr events and does not block.
2. Dangerous command with UI emits active before prompt and inactive after prompt.
3. Dangerous command allowed by user returns no block result.
4. Dangerous command denied by user returns `{ block: true, reason: "Bloqueado pelo usuário" }`.
5. Dangerous command where the prompt throws still emits inactive before propagating or returning the existing behavior.
6. Dangerous command without UI blocks directly and emits no Herdr blocked events.
7. Herdr event emission failure does not break the permission prompt.

Manual validation inside Herdr:

1. Launch Pi in a Herdr pane.
2. Trigger a dangerous bash tool call that invokes the permission gate.
3. Confirm the Herdr pane changes to `blocked` while the permission prompt is open.
4. Answer the prompt.
5. Confirm the Herdr pane no longer shows `blocked` after the input is handled.
6. Test both allow and deny flows.

---

## 9. Error Handling

Herdr signaling must be best-effort only. If `pi.events.emit` throws or no Herdr listener is installed:

- the permission prompt must still appear
- the permission decision must still be enforced
- the agent must not crash because of Herdr integration

The permission gate is security-sensitive. Herdr status updates must not weaken or bypass blocking behavior.

---

## 10. Success Criteria

The change is successful when:

- the generic bridge extension is removed
- settings no longer reference the removed bridge extension
- dangerous commands that require permission make Herdr report the pane as `blocked` while waiting for input
- Herdr exits `blocked` after the user responds or the prompt fails
- non-interactive dangerous commands remain blocked by default
- safe commands are unaffected
- automated tests pass
