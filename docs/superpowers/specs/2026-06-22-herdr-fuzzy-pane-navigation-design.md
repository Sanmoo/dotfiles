# Herdr fuzzy pane navigation design

## Goal

Replace the current `prefix+/` Herdr navigation binding with a fuzzy search over every pane in the current Herdr session. Each selectable item represents a pane and is searched by its full hierarchical name:

```text
<workspace> / <tab> / <pane>
```

Selecting an item focuses the corresponding workspace, tab, and pane. Canceling the picker leaves focus unchanged.

## User experience

- Press `ctrl+a`, then `/`.
- Herdr opens a fuzzy search UI or temporary picker.
- The picker lists all currently available panes with full context, for example:

  ```text
  personal / coding / pi
  personal / coding / shell
  work / backend / claude
  work / deploy / logs
  ```

- Filtering matches against the full concatenated string, not only the pane name.
- Pressing Enter focuses the selected pane.
- Pressing Esc or canceling the picker does nothing.

## Preferred approach: native Herdr support

First, check whether the installed Herdr version exposes a native key action for fuzzy navigation across panes, tabs, and workspaces.

If native support exists and searches the full contextual name, configure it on `prefix+/` and remove or replace the current binding:

```toml
goto = "prefix+/"
```

This is preferred because it keeps the UX integrated with Herdr and avoids maintaining an external script.

## Fallback approach: custom command

If Herdr does not expose suitable native support, replace `goto = "prefix+/"` with a custom command in `herdr/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+/"
type = "pane"
command = "~/.config/herdr/fuzzy-herdr-pane.sh"
description = "fuzzy focus pane"
```

The command type may be adjusted during implementation if Herdr requires `shell` for detached commands or `pane` for interactive fuzzy input.

The script should:

1. discover the current Herdr hierarchy;
2. emit one selectable row per pane using `<workspace> / <tab> / <pane>`;
3. run a fuzzy picker over those rows;
4. map the selected row back to stable Herdr identifiers;
5. request Herdr to focus the selected pane.

The script must avoid relying on display names as unique identifiers when Herdr exposes stable IDs. Display names are for search and presentation; IDs should be used for the focus action when available.

## Data source and focus mechanism

The implementation must investigate Herdr's available interfaces in this order:

1. documented config key or built-in key action;
2. Herdr CLI command;
3. local server/socket/API used by the client;
4. structured session files under `~/.config/herdr`, if they are safe and current enough;
5. as a last resort, no-op with a clear error explaining that Herdr does not expose the required state/control interface.

The fallback script should not mutate Herdr session files directly unless Herdr explicitly documents that as safe.

## Error handling

- If there are no panes, show a clear message and exit without changing focus.
- If the fuzzy picker is missing, show which dependency is required.
- If Herdr state cannot be read, show a clear diagnostic and exit non-zero.
- If the selected pane can no longer be focused because it disappeared, show a clear message and exit non-zero.
- Canceling the picker must exit successfully or harmlessly without changing focus.

## Testing and verification

Verification should include:

- inspecting `config.toml` to confirm `prefix+/` no longer invokes the old non-fuzzy `goto` behavior;
- testing the hierarchy-to-display formatting with representative workspace/tab/pane names;
- testing that canceling the picker does not emit a focus request;
- testing duplicate display names if stable IDs are available;
- manually invoking `ctrl+a` then `/` in Herdr to confirm the picker opens and focusing a pane works.

Automated tests are only required for script logic that can run without a live Herdr server. Live focus behavior may be verified manually because it depends on an active Herdr session.

## Scope

Expected files:

- `herdr/.config/herdr/config.toml`
- possibly `herdr/.config/herdr/fuzzy-herdr-pane.sh`
- possibly test coverage for the fallback script

No AeroSpace or macOS workspace configuration should change.
