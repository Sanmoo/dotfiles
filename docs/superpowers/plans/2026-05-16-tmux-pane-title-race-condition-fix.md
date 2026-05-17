# Tmux Pane Title Race Condition Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `tmux-pane-title.ts` the authoritative pane title source by deferring its updates via `setTimeout(0)` so they execute after pi's built-in `updateTerminalTitle()`.

**Architecture:** Single-file fix. Remove redundant `ctx.ui.setTitle()` calls (overwritten by pi anyway), wrap `setTmuxPaneTitle()` in `setTimeout(0)` to run after pi's synchronous title update, and add a `turn_start` handler to catch `/rename`-triggered overrides.

**Tech Stack:** TypeScript (Pi extension), Node.js, tmux

---

### Task 1: Update `session_start` handler

**Files:**

- Modify: `pi/.pi/agent/extensions/tmux-pane-title.ts:42-46`

- [ ] **Step 1: Remove `ctx.ui.setTitle()` and wrap `setTmuxPaneTitle()` in `setTimeout(0)`**

Replace the `session_start` handler body:

```ts
pi.on("session_start", async (_event, ctx) => {
  const title = buildSessionTitle(pi);
  ctx.ui.setTitle(title);
  setTmuxPaneTitle(title);
});
```

With:

```ts
pi.on("session_start", async (_event, _ctx) => {
  const title = buildSessionTitle(pi);
  setTimeout(() => setTmuxPaneTitle(title), 0);
});
```

- [ ] **Step 2: Commit**

```bash
git add pi/.pi/agent/extensions/tmux-pane-title.ts
git commit -m "fix(tmux-pane-title): defer session_start title via setTimeout(0), remove ctx.ui.setTitle"
```

---

### Task 2: Update `agent_start` handler

**Files:**

- Modify: `pi/.pi/agent/extensions/tmux-pane-title.ts:49-53`

- [ ] **Step 1: Remove `ctx.ui.setTitle()` and wrap `setTmuxPaneTitle()` in `setTimeout(0)`**

Replace the `agent_start` handler body:

```ts
pi.on("agent_start", async (_event, ctx) => {
  const base = buildSessionTitle(pi);
  ctx.ui.setTitle(`● ${base}`);
  setTmuxPaneTitle(`● ${base}`);
});
```

With:

```ts
pi.on("agent_start", async (_event, _ctx) => {
  const base = buildSessionTitle(pi);
  setTimeout(() => setTmuxPaneTitle(`● ${base}`), 0);
});
```

- [ ] **Step 2: Commit**

```bash
git add pi/.pi/agent/extensions/tmux-pane-title.ts
git commit -m "fix(tmux-pane-title): defer agent_start title via setTimeout(0), remove ctx.ui.setTitle"
```

---

### Task 3: Update `agent_end` handler

**Files:**

- Modify: `pi/.pi/agent/extensions/tmux-pane-title.ts:56-60`

- [ ] **Step 1: Remove `ctx.ui.setTitle()` and wrap `setTmuxPaneTitle()` in `setTimeout(0)`**

Replace the `agent_end` handler body:

```ts
pi.on("agent_end", async (_event, ctx) => {
  const title = buildSessionTitle(pi);
  ctx.ui.setTitle(title);
  setTmuxPaneTitle(title);
});
```

With:

```ts
pi.on("agent_end", async (_event, _ctx) => {
  const title = buildSessionTitle(pi);
  setTimeout(() => setTmuxPaneTitle(title), 0);
});
```

- [ ] **Step 2: Commit**

```bash
git add pi/.pi/agent/extensions/tmux-pane-title.ts
git commit -m "fix(tmux-pane-title): defer agent_end title via setTimeout(0), remove ctx.ui.setTitle"
```

---

### Task 4: Add `turn_start` handler

**Files:**

- Modify: `pi/.pi/agent/extensions/tmux-pane-title.ts` (insert after `agent_end` handler, before `session_shutdown`)

- [ ] **Step 1: Add `turn_start` event handler**

Insert after the `agent_end` handler block and before the `session_shutdown` comment:

```ts
// Reapply title at the start of each turn — catches /rename overrides
pi.on("turn_start", async (_event, _ctx) => {
  const title = buildSessionTitle(pi);
  setTimeout(() => setTmuxPaneTitle(title), 0);
});
```

- [ ] **Step 2: Commit**

```bash
git add pi/.pi/agent/extensions/tmux-pane-title.ts
git commit -m "feat(tmux-pane-title): add turn_start handler to catch /rename overrides"
```

---

### Task 5: Verification

- [ ] **Step 1: Reload extensions and verify initial title**

In a tmux session, start pi and run `/reload`. Verify the pane title shows `pi: <cwd>` (not `π - ...`).

```bash
# Check current pane title
tmux display-message -p '#T'
```

- [ ] **Step 2: Verify agent working indicator**

Send a prompt to pi. While the agent is working, verify the pane title shows `● pi: <name>`.

```bash
tmux display-message -p '#T'
```

- [ ] **Step 3: Verify after agent ends**

After the agent finishes, verify the pane title reverts to `pi: <name>` or `pi: <cwd>`.

```bash
tmux display-message -p '#T'
```

- [ ] **Step 4: Verify after `/rename`**

Run `/rename TestTitle` and verify the pane title updates to `pi: TestTitle`.

```bash
tmux display-message -p '#T'
```

- [ ] **Step 5: Verify after `/name`**

Run `/name CustomName` and verify the pane title updates to `pi: CustomName`.

```bash
tmux display-message -p '#T'
```

- [ ] **Step 6: Verify shutdown cleanup**

Exit pi (`Ctrl+D` or `/exit`). Verify the pane title resets to the cwd basename (bare, no prefix).

```bash
tmux display-message -p '#T'
```

---

### Complete file after all changes

For reference, the final state of `tmux-pane-title.ts`:

```ts
/**
 * tmux Pane Title Extension
 *
 * Renames the current tmux pane to match the pi session name.
 * - If a name was set via /name, uses that
 * - Otherwise uses <cwd-basename>
 *
 * Uses setTimeout(0) to defer title updates so they execute after
 * pi's built-in updateTerminalTitle(), preventing the "π -" prefix
 * from appearing.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import path from "node:path";
import { execFile } from "node:child_process";

function buildSessionTitle(pi: ExtensionAPI): string {
  const sessionName = pi.getSessionName();
  if (sessionName && sessionName.trim()) {
    return `pi: ${sessionName}`;
  }
  // Fallback: cwd basename
  const cwd = path.basename(process.cwd());
  return `pi: ${cwd}`;
}

function setTmuxPaneTitle(title: string) {
  if (!process.env.TMUX || !process.env.TMUX_PANE) return;
  execFile(
    "tmux",
    ["select-pane", "-t", process.env.TMUX_PANE!, "-T", title],
    (err) => {
      // Silently ignore errors (e.g., tmux not available, pane detached)
      if (err && err.code !== "ENOENT") {
        // Only log unexpected errors
      }
    },
  );
}

export default function (pi: ExtensionAPI) {
  // When session starts, set the initial title
  pi.on("session_start", async (_event, _ctx) => {
    const title = buildSessionTitle(pi);
    setTimeout(() => setTmuxPaneTitle(title), 0);
  });

  // When agent starts working, show a spinner/indicator
  pi.on("agent_start", async (_event, _ctx) => {
    const base = buildSessionTitle(pi);
    setTimeout(() => setTmuxPaneTitle(`● ${base}`), 0);
  });

  // When agent finishes, restore clean title
  pi.on("agent_end", async (_event, _ctx) => {
    const title = buildSessionTitle(pi);
    setTimeout(() => setTmuxPaneTitle(title), 0);
  });

  // Reapply title at the start of each turn — catches /rename overrides
  pi.on("turn_start", async (_event, _ctx) => {
    const title = buildSessionTitle(pi);
    setTimeout(() => setTmuxPaneTitle(title), 0);
  });

  // Clean up on shutdown
  pi.on("session_shutdown", async (_event, ctx) => {
    if (process.env.TMUX && process.env.TMUX_PANE) {
      // Reset to cwd basename when pi exits
      execFile(
        "tmux",
        [
          "select-pane",
          "-t",
          process.env.TMUX_PANE!,
          "-T",
          path.basename(process.cwd()),
        ],
        () => {},
      );
    }
    ctx.ui.setTitle("");
  });
}
```
