# Herdr Keybindings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Herdr so `prefix + l` reloads config and `prefix + N` renames the current workspace.

**Architecture:** This is a small TOML configuration change in the existing `[keys]` section. Keep the existing prefix and all unrelated bindings unchanged.

**Tech Stack:** Herdr `config.toml`, git, shell verification with `grep`.

---

## File Structure

- Modify: `herdr/.config/herdr/config.toml`
  - Owns Herdr runtime configuration, including prefix-mode keybindings under `[keys]`.
- No test files are required because this repository stores dotfiles rather than executable code for Herdr.

### Task 1: Update Herdr keybindings

**Files:**
- Modify: `herdr/.config/herdr/config.toml`

- [ ] **Step 1: Inspect current keybindings**

Run:

```bash
grep -nE 'prefix|reload_config|rename_workspace' herdr/.config/herdr/config.toml
```

Expected output includes these current/relevant lines:

```text
prefix = "ctrl+a"
reload_config = "R"
# rename_workspace = "shift+n"
```

- [ ] **Step 2: Edit `reload_config`**

In `herdr/.config/herdr/config.toml`, replace:

```toml
reload_config = "R"     # optional shortcut to reload config.toml without restarting
```

with:

```toml
reload_config = "l"     # optional shortcut to reload config.toml without restarting
```

- [ ] **Step 3: Enable `rename_workspace`**

In `herdr/.config/herdr/config.toml`, replace:

```toml
# rename_workspace = "shift+n"
```

with:

```toml
rename_workspace = "shift+n"
```

- [ ] **Step 4: Verify requested bindings**

Run:

```bash
grep -nE 'prefix|reload_config|rename_workspace' herdr/.config/herdr/config.toml
```

Expected output includes:

```text
prefix = "ctrl+a"
reload_config = "l"     # optional shortcut to reload config.toml without restarting
rename_workspace = "shift+n"
```

- [ ] **Step 5: Review diff**

Run:

```bash
git diff -- herdr/.config/herdr/config.toml
```

Expected diff changes only `reload_config` and `rename_workspace` in the `[keys]` section.

- [ ] **Step 6: Commit implementation**

Run:

```bash
git add herdr/.config/herdr/config.toml docs/superpowers/plans/2026-05-19-herdr-keybindings.md
git commit -m "Update Herdr workspace keybindings"
```

Expected result: commit succeeds with the Herdr config change and this implementation plan.
