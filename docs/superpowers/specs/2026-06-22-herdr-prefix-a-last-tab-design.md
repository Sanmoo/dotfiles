# Herdr prefix+a Last Tab Shortcut Design

## Goal

Map `prefix+a` in Herdr to switch back to the previously focused tab. This replaces the current `prefix+a` binding for the previously focused pane.

## Current State

`herdr/.config/herdr/config.toml` sets:

```toml
prefix = "ctrl+a"
last_pane = "prefix+a"  # switch to the previously focused pane
```

The desired behavior is tab-level navigation, not pane-level navigation.

## Design

Update the Herdr key configuration so:

- `prefix+a` invokes Herdr's native previous/last-tab action, if available.
- `last_pane` is disabled so it no longer captures `prefix+a`.
- No replacement shortcut is added for `last_pane`.

The target configuration should prefer a native key field such as `last_tab` if Herdr supports it. If this installed Herdr version does not support a native last-tab field, use a custom command only as a fallback.

## Files

- `herdr/.config/herdr/config.toml`

## Testing

- Validate the config syntax.
- Search the installed Herdr documentation or binary help/config references to confirm the correct native key name.
- If a custom fallback is needed, add a small shell test for the script.

## Out of Scope

- Changing the prefix key.
- Adding a new shortcut for last pane.
- Changing other tab, pane, workspace, or agent bindings.
