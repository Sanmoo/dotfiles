# Herdr Gruvbox Contrast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve selected/focused row contrast in Herdr while keeping the base gruvbox theme.

**Architecture:** This is a configuration-only change. Keep `theme.name = "gruvbox"` and add a `[theme.custom]` override table immediately after the existing theme comments so Herdr applies a balanced gruvbox contrast layer.

**Tech Stack:** TOML configuration for Herdr, Herdr CLI reload command, git.

---

## File structure

- Modify: `herdr/.config/herdr/config.toml`
  - Responsibility: User Herdr configuration, including theme selection and custom theme token overrides.
- Read-only reference: `docs/superpowers/specs/2026-05-31-herdr-gruvbox-contrast-design.md`
  - Responsibility: Approved design and visual intent.

---

### Task 1: Add balanced gruvbox contrast overrides

**Files:**
- Modify: `herdr/.config/herdr/config.toml:9-20`

- [ ] **Step 1: Inspect current theme block**

Run:

```bash
sed -n '9,22p' herdr/.config/herdr/config.toml
```

Expected output includes:

```toml
[theme]
name = "gruvbox"

# Override individual color tokens on top of the base theme.
# Accepts: hex (#rrggbb), named colors, rgb(r,g,b), or panel_bg = "reset"
# [theme.custom]
# panel_bg = "reset"
# accent = "#f5c2e7"
# red = "#ff6188"
# green = "#a6e3a1"
```

- [ ] **Step 2: Add the custom theme override table**

Replace the commented sample block:

```toml
# [theme.custom]
# panel_bg = "reset"
# accent = "#f5c2e7"
# red = "#ff6188"
# green = "#a6e3a1"
```

with:

```toml
[theme.custom]
# Balanced gruvbox contrast layer: keep the base palette, but make
# selected/focused Herdr surfaces visually distinct from the normal background.
accent = "#fe8019"
surface = "#3c3836"
yellow = "#fabd2f"
```

- [ ] **Step 3: Verify the config parses/reloads**

Run:

```bash
herdr server reload-config
```

Expected output: command exits with status 0 and does not report a TOML parse error.

If Herdr rejects `surface` as an unknown token, replace `surface = "#3c3836"` with `surface_dim = "#3c3836"` and run `herdr server reload-config` again. The final config must reload successfully.

- [ ] **Step 4: Inspect the final theme block**

Run:

```bash
sed -n '9,24p' herdr/.config/herdr/config.toml
```

Expected output includes either:

```toml
[theme.custom]
# Balanced gruvbox contrast layer: keep the base palette, but make
# selected/focused Herdr surfaces visually distinct from the normal background.
accent = "#fe8019"
surface = "#3c3836"
yellow = "#fabd2f"
```

or, only if `surface` was rejected by Herdr:

```toml
[theme.custom]
# Balanced gruvbox contrast layer: keep the base palette, but make
# selected/focused Herdr surfaces visually distinct from the normal background.
accent = "#fe8019"
surface_dim = "#3c3836"
yellow = "#fabd2f"
```

- [ ] **Step 5: Commit the config change**

Run:

```bash
git add herdr/.config/herdr/config.toml
git commit -m "config: improve herdr gruvbox contrast"
```

Expected: commit succeeds and includes only `herdr/.config/herdr/config.toml`.

---

### Task 2: Visual verification and fallback adjustment

**Files:**
- Modify if needed: `herdr/.config/herdr/config.toml:16-22`

- [ ] **Step 1: Visually inspect Herdr sidebar**

Look at the running Herdr UI after reload. Check both selected regions from the approved screenshot:

- selected workspace row in the `spaces` section
- selected/focused agent row in the `agents` section

Expected: both selected/focused regions have a visibly different background from the normal sidebar/panel background.

- [ ] **Step 2: If contrast is still too low, increase selected surface one step**

If the selected/focused background is still too close to the normal background, change the chosen surface token value from:

```toml
surface = "#3c3836"
```

or:

```toml
surface_dim = "#3c3836"
```

to:

```toml
surface = "#504945"
```

or:

```toml
surface_dim = "#504945"
```

Do not change `theme.name = "gruvbox"`.

- [ ] **Step 3: Reload after any fallback adjustment**

Run:

```bash
herdr server reload-config
```

Expected output: command exits with status 0 and does not report a TOML parse error.

- [ ] **Step 4: Commit fallback adjustment if made**

If Step 2 changed the file, run:

```bash
git add herdr/.config/herdr/config.toml
git commit -m "config: strengthen herdr selection contrast"
```

Expected: commit succeeds and includes only `herdr/.config/herdr/config.toml`.

If Step 2 made no change, do not create an empty commit.
