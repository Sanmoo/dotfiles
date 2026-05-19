# Herdr Tab Title Design

**Date:** 2026-05-19  
**Status:** Approved in brainstorming; awaiting user review of written spec  
**Scope:** Add a Pi extension that renames the current Herdr tab to match the Pi session name and restores the original tab label when appropriate.

---

## 1. Problem Statement

There is already a local Pi extension at `.pi/agent/extensions/tmux-pane-title.ts` that renames the active tmux pane to reflect the Pi session name. We want equivalent behavior for Herdr, a terminal workspace manager with tabs, panes, and a local CLI/socket API.

The desired behavior is:

- when Pi is running inside a Herdr-managed pane, rename the current Herdr tab to `pi: <session-name>`
- only apply the rename when Pi has an explicit session name
- when Pi has no explicit session name, leave the tab at its original/default Herdr label
- when Pi shuts down, restore the original tab label that existed before Pi renamed it

This work is limited to tab naming. It does not change agent-state reporting, pane naming, or workspace naming.

---

## 2. Goals and Non-Goals

### Goals

- Add a Herdr-specific tab-title extension for Pi.
- Keep the behavior conceptually aligned with the existing tmux title extension.
- Rename only the tab that contains the current Pi process.
- Restore the original tab label on shutdown.
- Avoid breaking Pi if Herdr is unavailable or returns errors.
- Avoid editing Herdr-managed installed integration files.

### Non-Goals

- Do not modify `.pi/agent/extensions/tmux-pane-title.ts`.
- Do not add activity indicators such as `●` or busy/idle prefixes.
- Do not rename Herdr panes or workspaces.
- Do not modify the official `herdr-agent-state.ts` integration installed by `herdr integration install pi`.
- Do not add generalized abstraction for multiple multiplexers at this stage.

---

## 3. Context and Constraints

### Existing local reference

The current tmux extension uses `pi.getSessionName()` to derive a title and updates tmux on Pi lifecycle events. That file is a useful behavioral reference, but Herdr has different semantics:

- tmux renames panes
- Herdr renames tabs via `herdr tab rename <tab_id> <label>`
- Herdr tab labels should be restored to the original observed label rather than reconstructed heuristically

### Herdr capabilities confirmed during research

Herdr exposes:

- `herdr pane get <pane_id>` → includes the current `tab_id`
- `herdr tab get <tab_id>` → can be used to inspect the current tab label
- `herdr tab rename <tab_id> <label>` → renames the tab

When running inside Herdr, the environment includes at least:

- `HERDR_ENV=1`
- `HERDR_SOCKET_PATH`
- `HERDR_PANE_ID`

The official Herdr Pi integration is aimed at agent-state reporting over the socket API and is installed to `~/.pi/agent/extensions/herdr-agent-state.ts`. That file is managed by Herdr and should not be the place for local custom tab-title behavior.

### Constraint: preserve update safety

If we modify the Herdr-installed integration directly, `herdr integration install pi` or future Herdr upgrades may overwrite our local customization. To avoid that, the tab-title behavior should live in its own extension file under this repo.

---

## 4. Proposed Architecture

Create a new local Pi extension:

- `.pi/agent/extensions/herdr-tab-title.ts`

This extension has one responsibility: synchronize the label of the current Herdr tab with the Pi session name while Pi is running.

### Responsibilities

The extension will:

1. detect whether Pi is running inside Herdr
2. resolve the current `tab_id` from the current `pane_id`
3. read and store the original tab label once at session start
4. compute the desired Pi-driven tab label from `pi.getSessionName()`
5. rename the current tab only when needed
6. restore the original tab label on shutdown

### Out of scope for the extension

The extension will not:

- report agent working/blocked/idle state to Herdr
- manage pane labels
- manage workspace labels
- coordinate with tmux behavior

---

## 5. Data and State Model

The extension only needs in-memory session-local state.

### Stored state

- `tabId: string | null` — resolved once from the active Herdr pane
- `originalTabLabel: string | null` — label captured from Herdr before Pi applies any rename
- `lastAppliedLabel: string | null` — last label this extension attempted to set, to avoid redundant renames
- `enabled: boolean` — whether the extension is running in a valid Herdr context

### Why state is in memory only

This behavior is only relevant for the current live Pi process. Persisting it across restarts is unnecessary and could produce incorrect restoration behavior if the Herdr session changed while Pi was not running.

---

## 6. Title Rules

### Desired Pi-managed title

If Pi has an explicit session name:

- target label = `pi: <session-name>`

### No explicit session name

If `pi.getSessionName()` is empty or blank:

- do not invent a fallback such as cwd
- restore the original tab label captured at session start

### Shutdown

On `session_shutdown`:

- restore the original tab label captured at session start

### Rationale

The user explicitly wants Herdr to behave differently from the tmux fallback behavior. For Herdr, the priority is to preserve the real existing tab label/default rather than compute a synthetic fallback.

---

## 7. Event Model

The extension should use the smallest set of Pi lifecycle events that fully supports the feature.

### `session_start`

At session start, the extension will:

1. verify that it is running inside Herdr
2. resolve `tabId` from `HERDR_PANE_ID`
3. read and store `originalTabLabel`
4. compute the current desired label
5. apply a rename if and only if an explicit Pi session name already exists

### `turn_start`

At the start of every turn, the extension will:

1. compute the current desired label from `pi.getSessionName()`
2. if a name exists, ensure the tab is `pi: <name>`
3. if no name exists, restore the original label
4. skip any Herdr call when the desired label equals `lastAppliedLabel`

This is the mechanism that catches user-triggered session renames during the life of the session.

### `session_shutdown`

On shutdown, the extension will:

1. attempt to restore the original label
2. ignore operational errors

### Events intentionally not used

The extension should not use `agent_start` or `agent_end`, because:

- the user does not want activity indicators
- using them would generate extra renames with no product value

---

## 8. Herdr Interaction Strategy

### Detecting Herdr context

The extension is active only when all of the following are true:

- `HERDR_ENV === "1"`
- `HERDR_PANE_ID` exists
- the `herdr` binary is callable from the current process environment

If these conditions are not met, the extension becomes a no-op.

### Resolving the current tab

The extension should treat `HERDR_PANE_ID` as the authoritative handle for the current Pi process. It should call:

- `herdr pane get <HERDR_PANE_ID>`

and extract the tab identifier from the response.

### Reading the original tab label

Once the tab id is known, the extension should call:

- `herdr tab get <tab_id>`

and store the visible/current label from the returned tab info as `originalTabLabel`.

### Applying a rename

To rename the tab, the extension should call:

- `herdr tab rename <tab_id> <label>`

### Restoring a label

Restoration is the same operation as rename, using the stored `originalTabLabel`.

---

## 9. Boundary and Error-Handling Decisions

### Fixed `tabId` for the session

The extension will resolve the `tabId` once during `session_start` and treat it as fixed for the remainder of the Pi session.

#### Why this is the chosen behavior

A more dynamic design could re-resolve the tab on every turn, but that introduces ambiguity during restoration:

- if the pane moved across tabs
- if Herdr compacted ids
- if the extension followed a new tab mid-session

then shutdown restoration could affect the wrong tab or lose track of the original label. Fixing the `tabId` for the session keeps the behavior deterministic.

### Silent failure policy

Any Herdr communication failure should be treated as non-fatal. Examples:

- `herdr` is not available
- `pane get` or `tab get` returns invalid JSON
- the tab no longer exists
- the socket is unavailable

In all such cases:

- Pi continues normally
- the extension performs no further rename action for that operation
- optional debug logging is acceptable, but the user experience must remain unaffected

### Redundant call suppression

If the desired label equals the last label the extension attempted to apply, the extension should skip `herdr tab rename`. This reduces unnecessary external process calls and avoids churn.

---

## 10. File-Level Design

### New file

- `.pi/agent/extensions/herdr-tab-title.ts`

### Internal helper structure

The extension should be organized into small focused helpers, such as:

- `buildSessionTitle(pi): string | null`
  - returns `pi: <name>` when a non-blank session name exists
  - returns `null` when no explicit session name exists

- `isHerdrContext(): boolean`
  - validates required environment variables

- `runHerdrJson(args): Promise<any | null>`
  - executes `herdr` commands that return JSON and safely parses the response

- `resolveCurrentTabId(): Promise<string | null>`
  - calls `herdr pane get`

- `readOriginalTabLabel(tabId): Promise<string | null>`
  - calls `herdr tab get`

- `setTabLabel(tabId, label): Promise<void>`
  - calls `herdr tab rename`

- `syncTabLabel()`
  - applies either the Pi-managed label or the original label depending on session-name presence

- `restoreOriginalTabLabel()`
  - used during shutdown and no-name fallback

The exact function names may vary, but the structure should preserve these responsibilities.

---

## 11. Validation Plan

### Static validation

Before claiming the work is complete, validate that:

- the new TypeScript file has no obvious syntax/type issues
- imports and Node APIs match the style used by existing Pi extensions
- the extension loads without affecting Pi startup outside Herdr

### Manual functional validation

Run Pi inside Herdr and verify the following sequence:

1. start in a Herdr tab with an existing default or custom label
2. launch Pi in that tab
3. confirm that, before any explicit Pi session naming, the tab label remains unchanged
4. set a Pi session name
5. confirm that the tab label becomes `pi: <name>`
6. change the Pi session name again
7. confirm that the tab label updates accordingly
8. end the Pi session
9. confirm that the original tab label is restored

### Failure-mode validation

Also verify that:

- running Pi outside Herdr causes no errors and no rename attempts
- Herdr CLI failures do not break the Pi session
- empty or blank session names restore the original tab label rather than applying cwd-based fallback

---

## 12. Success Criteria

The feature is successful when all of the following are true:

- Pi running inside Herdr can rename the current Herdr tab to `pi: <session-name>`
- the rename happens only when the session has an explicit non-blank name
- tabs without an explicit Pi session name retain or return to their original label
- shutdown restores the original label captured at session start
- Herdr failures do not interrupt Pi
- the implementation is isolated to a new local extension file and does not modify Herdr-managed integration assets

---

## 13. Chosen Approach Summary

Use a dedicated local Pi extension for Herdr tab naming rather than extending the official Herdr Pi integration or creating a premature shared abstraction across tmux and Herdr.

This keeps the feature:

- local
- deterministic
- easy to maintain
- resilient to upstream Herdr integration updates

It also best matches the user's requested behavior: `pi: <name>` while named, otherwise restore the original/default Herdr tab label.
