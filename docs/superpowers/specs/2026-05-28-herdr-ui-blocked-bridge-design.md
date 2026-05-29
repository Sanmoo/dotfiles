# Herdr UI Blocked Bridge Design

**Date:** 2026-05-28  
**Status:** Approved in brainstorming; awaiting user review of written spec  
**Scope:** Add a local Pi extension that marks Herdr agent state as blocked while explicit Pi UI dialogs are waiting for user input.

---

## 1. Problem Statement

Some Pi extensions block the agent while waiting for user input through Pi UI dialogs. Herdr already has an installed Pi agent-state integration that can report agent states such as `working`, `idle`, and `blocked`, but the blocked state is only triggered when another extension emits the internal `herdr:blocked` event.

The current gap is that extensions using explicit Pi dialogs, such as `ctx.ui.select`, do not automatically notify Herdr that the agent is waiting for the user.

We want a generic solution for explicit dialogs so extensions do not each need to implement their own Herdr signaling.

---

## 2. Goals and Non-Goals

### Goals

- Mark the Herdr agent as `blocked` while explicit Pi UI dialogs wait for input.
- Support any extension that uses the wrapped explicit dialog methods.
- Avoid editing the Herdr-managed integration file at `~/.pi/agent/extensions/herdr-agent-state.ts`.
- Use the existing `herdr:blocked` event contract already consumed by `herdr-agent-state.ts`.
- Ensure Herdr leaves `blocked` state when the dialog resolves, rejects, or is cancelled.
- Load the bridge before other local extensions that may show dialogs.

### Non-Goals

- Do not wrap `ctx.ui.custom()`.
- Do not infer blocking from arbitrary async work.
- Do not communicate directly with the Herdr socket or CLI from the new bridge.
- Do not modify the Herdr-managed `herdr-agent-state.ts` file.
- Do not require individual dialog-using extensions, such as `permission-gate.ts`, to be modified for normal operation.

---

## 3. Existing Context

The installed Herdr Pi integration at `~/.pi/agent/extensions/herdr-agent-state.ts` already contains logic equivalent to:

```ts
pi.events.on("herdr:blocked", (data) => {
  // active=true increments blocked count and publishes blocked state
  // active=false decrements blocked count and republishes desired state
});
```

It reports the blocked state to Herdr through `pane.report_agent`. It also keeps a blocked counter, which means nested or overlapping blocked sections can be represented safely as long as every `active: true` is paired with an `active: false`.

The file is managed by Herdr and explicitly warns that reinstalling or updating the integration overwrites it. Therefore, local behavior should be implemented beside it, not inside it.

---

## 4. Proposed Architecture

Create a local Pi extension:

- `pi/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts`

The extension has one responsibility: bridge explicit Pi UI dialogs to Herdr's existing blocked-state event.

It will wrap these explicit dialog methods when present on `ctx.ui`:

- `select`
- `confirm`
- `input`
- `editor`

For each wrapped method, it will:

1. emit `pi.events.emit("herdr:blocked", { active: true, label: "Aguardando input" })`
2. call the original UI method with the original `this` value and arguments
3. emit `pi.events.emit("herdr:blocked", { active: false })` in a `finally` block

The extension does not need to know whether the current process is inside Herdr. If the Herdr integration is not loaded or is inactive, the emitted event has no practical effect.

---

## 5. Loading and Ordering Requirements

The bridge must run before extensions that call explicit UI dialogs in the same Pi event.

For example, if `permission-gate.ts` calls `ctx.ui.select(...)` in a `tool_call` handler, then the bridge must receive that `tool_call` event first so it can replace `ctx.ui.select` with the wrapped version before `permission-gate.ts` invokes it.

If the dialog-using extension runs first, it can call the original UI method before the bridge has a chance to wrap it. The bridge might protect future calls, but it would be too late for that dialog.

To make this reliable:

- name the extension `00-herdr-ui-blocked-bridge.ts` so auto-discovery order favors early loading
- list it first in platform settings

Both platform settings should include the extension as the first item:

```json
"extensions": [
  "~/.pi/agent/extensions/00-herdr-ui-blocked-bridge.ts",
  "~/.pi/agent/extensions/herdr-subagent-guard.ts"
]
```

Files to update:

- `pi-linux/.pi/agent/settings.json`
- `pi-mac/.pi/agent/settings.json`

The extension file itself lives in the shared `pi/.pi/agent/extensions/` tree so it can be stowed into `~/.pi/agent/extensions/` on both platforms.

---

## 6. Wrapping Strategy

The extension should use an idempotent wrapper function such as `wrapUi(ui)`.

`wrapUi(ui)` should:

- no-op when `ui` is missing
- no-op when the same `ui` object has already been wrapped
- mark wrapped objects with a private `Symbol`
- only wrap methods that exist and are functions
- preserve method behavior, return values, `this`, and arguments

Pseudocode:

```ts
const wrappedMarker = Symbol("herdr-ui-blocked-bridge.wrapped");

function wrapDialogMethod(ui, methodName) {
  const original = ui[methodName];
  if (typeof original !== "function") return;

  ui[methodName] = async function wrappedDialog(...args) {
    safeEmitBlocked(true);
    try {
      return await original.apply(this, args);
    } finally {
      safeEmitBlocked(false);
    }
  };
}
```

`safeEmitBlocked` should catch and ignore errors so a Herdr signaling problem never breaks Pi's UI dialog.

---

## 7. Event Coverage

The bridge should install wrappers whenever it receives an event with a usable `ctx.ui`.

Expected event hooks:

- `session_start`
- `before_agent_start`
- `agent_start`
- `tool_call`
- optionally other common lifecycle events that receive `ctx`

The implementation should remain conservative: adding wrapper installation to an event is safe because wrapping is idempotent, but the extension should not add behavior beyond wrapping dialog methods.

The most important event for the known local case is `tool_call`, because `permission-gate.ts` opens its confirmation dialog during `tool_call`.

---

## 8. Data Flow

1. A Pi extension calls an explicit UI dialog such as `ctx.ui.select(...)`.
2. The wrapped method emits:

   ```ts
   pi.events.emit("herdr:blocked", {
     active: true,
     label: "Aguardando input",
   });
   ```

3. `herdr-agent-state.ts` receives the event, increments its blocked counter, and reports `state: "blocked"` to Herdr.
4. The dialog waits for the user's response.
5. When the dialog finishes, the wrapper's `finally` emits:

   ```ts
   pi.events.emit("herdr:blocked", { active: false });
   ```

6. `herdr-agent-state.ts` decrements its blocked counter and republishes the desired state, normally returning to `working` if the agent is still active or `idle` after the usual idle debounce.

---

## 9. Error Handling

The bridge should be fail-open for Pi behavior.

- If `pi.events.emit` throws, catch and ignore the error.
- If the original dialog throws, preserve the original throw after emitting `active: false`.
- If the user cancels a dialog, still emit `active: false`.
- If Herdr is unavailable, do not change dialog behavior.
- If the Herdr integration is not loaded, do not change dialog behavior.

The most important invariant is: every successful `active: true` attempt should be paired with an `active: false` attempt in `finally`.

---

## 10. Validation Plan

### Static validation

- Check TypeScript syntax for the new extension.
- Check JSON validity for both platform settings files.
- Confirm the new extension is the first item in both `extensions` arrays.

### Manual validation inside Herdr

Use a known explicit-dialog extension, such as `permission-gate.ts`:

1. Start Pi in a Herdr-managed pane.
2. Trigger a dangerous bash command that opens a confirmation dialog.
3. Confirm Herdr shows the agent as blocked with label `Aguardando input` while the dialog is open.
4. Answer the dialog.
5. Confirm Herdr leaves blocked state.

### Manual validation outside Herdr

1. Start Pi outside Herdr.
2. Trigger an explicit UI dialog.
3. Confirm the dialog behaves normally and no errors appear.

### Ordering validation

- Confirm `pi-linux/.pi/agent/settings.json` lists `00-herdr-ui-blocked-bridge.ts` before `herdr-subagent-guard.ts`.
- Confirm `pi-mac/.pi/agent/settings.json` lists `00-herdr-ui-blocked-bridge.ts` before `herdr-subagent-guard.ts`.

---

## 11. Success Criteria

The feature is successful when:

- explicit dialogs from any extension can mark the Herdr agent state as blocked
- the displayed blocked label is `Aguardando input`
- `ctx.ui.custom()` is not wrapped
- blocked state is cleared after dialog completion, cancellation, or error
- no Herdr-managed files are modified
- Linux and macOS Pi settings load the bridge first
- Pi behavior outside Herdr remains unchanged

---

## 12. Chosen Approach Summary

Use a dedicated local bridge extension loaded early. It wraps explicit `ctx.ui` dialog methods and emits the existing `herdr:blocked` event that the Herdr-managed agent-state integration already understands.

This keeps the design generic for dialog-using extensions, avoids editing managed Herdr files, and limits behavior to clear user-input wait points.
