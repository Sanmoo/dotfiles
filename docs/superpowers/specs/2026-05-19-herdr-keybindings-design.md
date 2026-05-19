# Herdr keybindings design

## Goal

Update the Herdr prefix-mode keybindings so that:

- `prefix + l` reloads the Herdr configuration.
- `prefix + N` renames the current workspace.

The configured prefix remains `ctrl+a`.

## Approach

Make the smallest possible change in `herdr/.config/herdr/config.toml` under the `[keys]` section:

- Change `reload_config` from `"R"` to `"l"`.
- Enable `rename_workspace` with `"shift+n"`, matching Herdr's syntax for uppercase `N`.

No other keybindings or UI settings should change.

## Verification

After editing, inspect the relevant `[keys]` lines and confirm the config contains the requested bindings.
