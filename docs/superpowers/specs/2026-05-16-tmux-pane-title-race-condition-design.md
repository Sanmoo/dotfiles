# Tmux Pane Title — Race Condition Fix

**Date:** 2026-05-16
**System:** Pi (agent)

## Goal

Ensure the `tmux-pane-title.ts` extension is the authoritative source for the tmux pane title, preventing pi's built-in `updateTerminalTitle()` from overwriting it.

## Problem

Pi has a built-in mechanism (`updateTerminalTitle()` in `interactive-mode.js`) that sets the terminal title via OSC escape sequence (`\x1b]0;...\x07`) to:

```
π - <sessionName> - <cwdBasename>
```

The user's `tmux-pane-title.ts` extension also sets the title (via `tmux select-pane -T`) to:

```
pi: <sessionName>      # idle
● pi: <sessionName>    # agent working
```

Both mechanisms compete. Pi's `updateTerminalTitle()` is called synchronously **after** extension event handlers fire, so the `π -` format wins. Additionally, `/rename` triggers `session_info_changed` (internal event, not exposed to extensions), which calls `updateTerminalTitle()` — but the extension has no handler for this.

### Call sites of pi's `updateTerminalTitle()`

| Location | Trigger |
|---|---|
| `rebindCurrentSession()` | Session init, resume, reload |
| `bindCurrentSessionExtensions()` | Before agent starts |
| `session_info_changed` handler | `/rename`, `/name`, session name change |

## Solution

Make the extension **postpone** its tmux pane title updates via `setTimeout(0)`, so they execute in the next microtask — after pi's synchronous `updateTerminalTitle()` has already run.

### Changes to `tmux-pane-title.ts`

#### 1. Remove `ctx.ui.setTitle()` calls

`ctx.ui.setTitle()` uses the same OSC escape mechanism as pi's built-in title and is always overwritten. Remove it from `session_start`, `agent_start`, `agent_end`. Keep only in `session_shutdown` to clear the terminal title on exit.

#### 2. Wrap `setTmuxPaneTitle()` in `setTimeout(0)`

In `session_start`, `agent_start`, and `agent_end`, change direct calls to `setTmuxPaneTitle(title)` to `setTimeout(() => setTmuxPaneTitle(title), 0)`. This defers execution to after pi's synchronous title update.

#### 3. Add `turn_start` handler

The `turn_start` event fires at the beginning of every conversation turn — including after `/rename` or `/name` commands. This handler reapplies the extension's title format, ensuring the pane title is corrected even when `session_info_changed` triggers pi's override.

```ts
pi.on("turn_start", async (_event, ctx) => {
    const title = buildSessionTitle(pi);
    setTimeout(() => setTmuxPaneTitle(title), 0);
});
```

#### 4. Keep `session_shutdown` unchanged

On shutdown, there is no more competition from pi. The direct `tmux select-pane -T <cwd>` reset and `ctx.ui.setTitle("")` work correctly.

### Handler summary

| Event | Before | After |
|---|---|---|
| `session_start` | `ctx.ui.setTitle(title)` + `setTmuxPaneTitle(title)` | `setTimeout(() => setTmuxPaneTitle(title), 0)` |
| `agent_start` | `ctx.ui.setTitle('● ' + base)` + `setTmuxPaneTitle('● ' + base)` | `setTimeout(() => setTmuxPaneTitle('● ' + base), 0)` |
| `agent_end` | `ctx.ui.setTitle(title)` + `setTmuxPaneTitle(title)` | `setTimeout(() => setTmuxPaneTitle(title), 0)` |
| `turn_start` | *(none)* | `setTimeout(() => setTmuxPaneTitle(title), 0)` |
| `session_shutdown` | `tmux select-pane -T <cwd>` + `ctx.ui.setTitle("")` | *(unchanged)* |

## Expected Behavior

| Scenario | Pane title |
|---|---|
| Session starts | `pi: <sessionName>` or `pi: <cwd>` |
| Agent working | `● pi: <sessionName>` |
| Agent idle | `pi: <sessionName>` or `pi: <cwd>` |
| After `/rename` | `pi: <newName>` |
| Pi exits | `<cwd>` (bare) |

The `π - ...` format from pi's built-in title no longer appears because the extension always reapplies its title after pi's update.
