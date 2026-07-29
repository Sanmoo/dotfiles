# Herdr Prefix+O Idle Agent Fix Design

## Goal

Make `prefix+o` focus next actionable Herdr agent when Herdr 0.7.5 reports completed or waiting agents as `idle`, while retaining compatibility with `blocked` and `done` states.

## Root Cause

`herdr/.config/herdr/focus-next-actionable-agent.sh` only accepts `blocked` and `done`. Current `herdr pane list` output uses `idle` and `working`, so idle agents are excluded and candidate list becomes empty.

## Behavior

An actionable agent has non-null `agent` and `agent_status` equal to one of:

- `idle`
- `blocked`
- `done`

Shortcut keeps existing circular selection:

1. Find focused pane index.
2. Find actionable agent pane indexes.
3. Select first candidate after focused pane.
4. Wrap to first candidate when none follows.
5. Exit successfully without focusing anything when no candidate exists.

## Implementation

Make minimal change to jq predicate in `focus-next-actionable-agent.sh`: include `idle` alongside existing compatible states. Do not change keybinding, command type, focus target selection, or empty-result handling.

## Testing

Add shell regression coverage using fake `herdr` executable and controlled `pane list` JSON. Verify:

- `idle` agent is selected.
- selection advances after focused pane and wraps.
- `blocked` and `done` remain accepted.
- `working` and non-agent panes remain excluded.
- no actionable candidate exits successfully without invoking `agent focus`.

Run focused regression test, then existing shell test suite.

## Scope

No Herdr configuration redesign, notification API integration, unrelated refactor, or keybinding change.
