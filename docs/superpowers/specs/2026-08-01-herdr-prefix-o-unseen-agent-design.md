# Herdr Prefix+O Unseen Agent Design

## Goal

Make `prefix+o` open the next Herdr agent whose status change has **not been viewed yet** (the green dot / pending state), working reliably long after the toast notification is gone.

## Background and Root Cause

Timeline:

1. Custom script `focus-next-actionable-agent.sh` cycled through all agents in `idle`, `blocked`, or `done` states (`4abd250`, `acbab80`, `1ecd42f`; spec `2026-07-29-herdr-prefix-o-idle-agent-design.md`).
2. `d2ebc21` replaced the custom script with the native `open_notification_target = "prefix+o"` shortcut.
3. `f3fb6f9` set `delivery = "herdr"` so in-app toasts keep the native target available.

The native `open_notification_target` jumps to a **transient notification queue**: once the toast expires or is dismissed, the queue is empty and `prefix+o` stops working — even though agents still show a green dot (`idle`) in the sidebar. The green dot reflects current agent state, not the notification queue, so the two views diverge.

## Behavior

- `prefix+o` selects the next agent that is actionable (`idle`, `blocked`, `done`) **and whose `state_change_seq` differs from the last viewed sequence for that pane**.
- An agent with no recorded entry counts as not viewed.
- Selection is circular: first candidate after the currently focused agent in `herdr agent list` order, wrapping to the first candidate when none follows.
- Focusing an agent via `prefix+o` records its current `state_change_seq` as viewed.
- An agent whose `state_change_seq` changes again (new green dot) becomes a candidate again.
- `working` agents and non-agent panes are never candidates.
- No candidates → exit 0 silently, no focus, state unchanged.

## Architecture

### `herdr/.config/herdr/focus-next-actionable-agent.sh` (restored + rewritten)

- Sources `herdr agent list` (fields: `pane_id`, `agent_status`, `state_change_seq`, `focused`).
- Reads/writes a persistent state file (below).
- Computes the target pane with `jq`.
- Runs `herdr agent focus <pane_id>`.
- Reuses the existing `need_cmd jq` pattern from `fuzzy-herdr-pane.sh`.
- Test hooks via env vars, following repo conventions:
  - `HERDR_BIN_PATH` (default `herdr`) — overrides the herdr CLI, as in the original script.
  - `HERDR_FOCUS_STATE_FILE` — overrides the state file path.

### State file

- Default path: `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/focus-state.json` (runtime data, **not committed**).
- Format: `{"seen": {"<pane_id>": <state_change_seq>}}`.
- Missing or corrupt state file → treated as empty (everything not viewed).
- Entries for panes no longer present in `herdr agent list` are pruned on each run.

### `herdr/.config/herdr/config.toml`

- Remove `open_notification_target = "prefix+o"` (set to `""`, disabled).
- Restore `[[keys.command]]` block:
  - `key = "prefix+o"`
  - `type = "shell"`
  - `command = "~/.config/herdr/focus-next-actionable-agent.sh"`
  - `description = "focus next agent with unseen state change"`
- Keep `delivery = "herdr"` (in-app toasts stay, they are no longer the navigation source).

### `.gitignore`

- Add `herdr/.config/herdr/focus-state.json` alongside the existing runtime-data ignores.

## Error Handling

- No candidates / empty list / missing `jq` → handled as in the previous script: silent success for empty, clear error for missing `jq` (`need_cmd`).
- Corrupt state JSON → ignored, treated as empty.
- `herdr agent list` failure → script fails loudly (existing behavior pattern).

## Testing

New `tests/focus-next-actionable-agent-test.sh` using a fake `herdr` executable via `HERDR_BIN_PATH` (fixture JSON for `agent list`, focus calls logged to a file), plus `HERDR_FOCUS_STATE_FILE` pointed at a temp file:

1. No agents → no focus, state unchanged.
2. Only `working` agents → no focus.
3. Unseen `idle` agent → focused and recorded as seen.
4. Same agent already seen → second call focuses nothing.
5. `state_change_seq` bumped → agent is a candidate again.
6. Circular order: selection advances after the focused agent and wraps.
7. Corrupt state file → treated as empty.
8. Panes removed from `agent list` → their state entries are pruned.

Update `tests/herdr-notification-target-test.sh` to the new expectations:

- `open_notification_target` is disabled/empty.
- A `[[keys.command]]` binding exists for `prefix+o` pointing at the script.
- `delivery = "herdr"` is preserved.

Run the new test plus the full existing `tests/` suite.

## Scope

No notification API integration, no Herdr upstream changes, no keybinding changes (still `prefix+o`), no changes to how other shortcuts work.
