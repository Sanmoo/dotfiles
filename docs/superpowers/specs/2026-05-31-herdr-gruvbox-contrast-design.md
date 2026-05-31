# Herdr gruvbox contrast design

## Goal

Improve visual contrast in the Herdr UI while keeping the base `gruvbox` theme. The selected/focused workspace and agent rows should have a clearly distinguishable background from the normal panel background.

## Scope

- Keep `theme.name = "gruvbox"`.
- Add a small `[theme.custom]` override layer in `herdr/.config/herdr/config.toml`.
- Prioritize the two problem areas shown in the screenshot: selected workspace and selected/focused agent row.
- Allow related accent/surface color changes if they improve overall theme readability.
- Do not change keybindings, layout, notification behavior, or agent behavior.

## Chosen approach

Use a balanced contrast layer:

- `accent = "#fe8019"` for focus, borders, and navigation UI.
- `surface = "#3c3836"` for selected/focused surfaces that must stand out from the gruvbox dark background.
- Keep the overall gruvbox palette identity: warm dark background, amber/orange highlights, and existing semantic colors.

This is stronger than the current subtle highlight, but less aggressive than a full high-contrast variant.

## Expected result

The selected workspace and selected/focused agent row should be visually obvious at a glance. The UI should still feel like gruvbox, not a new theme.

## Verification

After implementation:

1. Reload the Herdr config with `herdr server reload-config`.
2. Visually inspect the sidebar selected workspace and agent row.
3. Confirm the selected/focused regions are clearly distinct from the normal background.
4. If `surface` is not supported by the installed Herdr version, use the closest supported custom token discovered from Herdr configuration/runtime output and preserve the same visual intent.
