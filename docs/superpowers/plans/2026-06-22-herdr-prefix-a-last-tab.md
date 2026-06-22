# Herdr prefix+a Last Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Map Herdr `prefix+a` to switch to the previously focused tab and disable the previous `last_pane` shortcut.

**Architecture:** This is a focused configuration change in `herdr/.config/herdr/config.toml`. First confirm the installed Herdr key name for the previous/last-tab action, then edit only the relevant key bindings and validate the configuration.

**Tech Stack:** Herdr TOML configuration, shell commands, git.

## Global Constraints

- Preserve `prefix = "ctrl+a"`.
- `prefix+a` must switch to the previously focused tab, not the previously focused pane.
- Do not add a replacement shortcut for `last_pane`.
- Do not change unrelated workspace, tab, pane, or agent bindings.
- Prefer a native Herdr key field such as `last_tab`; use a custom command only if the installed Herdr version lacks a native previous/last-tab key.

---

## File Structure

- Modify: `herdr/.config/herdr/config.toml`
  - Responsibility: user Herdr configuration, including theme, key bindings, UI, and experimental options.
- No new script should be created if Herdr supports a native previous/last-tab key.
- If native support is absent, create: `herdr/.config/herdr/focus-last-tab.sh`
  - Responsibility: invoke Herdr CLI to focus the previously focused tab.
  - This fallback is only allowed after confirming no native key exists.

### Task 1: Confirm Herdr native last-tab key

**Files:**

- Read: `herdr/.config/herdr/config.toml`
- No modifications in this task.

**Interfaces:**

- Consumes: Installed `herdr` CLI/binary and current config.
- Produces: The exact key name to use in Task 2, preferably `last_tab`.

- [ ] **Step 1: Inspect current key bindings**

Run:

```bash
rg -n "last_|previous_tab|next_tab|\[keys\]" herdr/.config/herdr/config.toml
```

Expected: output includes the current `last_pane = "prefix+a"` binding and existing tab-related keys.

- [ ] **Step 2: Check Herdr help/config output for the last-tab action**

Run these commands, allowing failures because Herdr subcommands may differ by installed version:

```bash
(herdr --help || true) | rg -i "last|previous|tab|key|config" || true
(herdr config --help || true) | rg -i "last|previous|tab|key" || true
(herdr key --help || true) | rg -i "last|previous|tab|pane" || true
```

Expected: identify a native key/action for returning to the previously focused tab. If the output names `last_tab`, use `last_tab` in Task 2. If it names another field, use that exact field in Task 2 and update the comments accordingly.

- [ ] **Step 3: Search installed Herdr files for key names**

Run:

```bash
command -v herdr
strings "$(command -v herdr)" | rg -i "last_tab|last tab|previous_tab|last_pane|last pane" || true
```

Expected: output confirms whether `last_tab` or another native previous/last-tab key exists. If no native previous/last-tab key exists, stop before Task 2 and design the fallback script explicitly.

- [ ] **Step 4: Commit is not needed**

No files changed in this task, so do not commit.

### Task 2: Update `prefix+a` binding

**Files:**

- Modify: `herdr/.config/herdr/config.toml`

**Interfaces:**

- Consumes: Exact native previous/last-tab key name from Task 1.
- Produces: Config where `prefix+a` switches to the previously focused tab and `last_pane` is disabled.

- [ ] **Step 1: Edit the tab and pane bindings**

If Task 1 confirmed the native key is `last_tab`, replace this block:

```toml
next_tab = "ctrl+]"     # optional, unset by default
previous_tab = "ctrl+[" # optional, unset by default
last_pane = "prefix+a"  # switch to the previously focused pane
```

with:

```toml
next_tab = "ctrl+]"     # optional, unset by default
previous_tab = "ctrl+[" # optional, unset by default
last_tab = "prefix+a"   # switch to the previously focused tab
last_pane = ""          # disabled; prefix+a is used for last tab
```

If Task 1 found a different native key name, use the exact native key from Task 1 in place of `last_tab` and keep the `last_pane = ""` line.

- [ ] **Step 2: Verify the edit is limited to the intended lines**

Run:

```bash
git diff -- herdr/.config/herdr/config.toml
```

Expected: the diff only changes the last-pane binding area by adding/enabling the last-tab binding and disabling `last_pane`.

- [ ] **Step 3: Validate TOML syntax with Python**

Run:

```bash
python3 - <<'PY'
import tomllib
from pathlib import Path
path = Path('herdr/.config/herdr/config.toml')
with path.open('rb') as f:
    tomllib.load(f)
print('config.toml parses')
PY
```

Expected output:

```text
config.toml parses
```

- [ ] **Step 4: Run existing Herdr tests**

Run:

```bash
bash tests/fuzzy-herdr-pane-test.sh
bash tests/workq-launcher-herdr-pi-test.sh
```

Expected output includes:

```text
fuzzy-herdr-pane tests passed
```

and the workq launcher test exits with code 0.

- [ ] **Step 5: Check diagnostics for edited files**

Run the pi diagnostics tool or equivalent:

```bash
python3 - <<'PY'
import tomllib
from pathlib import Path
for path in [Path('herdr/.config/herdr/config.toml')]:
    with path.open('rb') as f:
        tomllib.load(f)
print('edited config diagnostics clean')
PY
```

Expected output:

```text
edited config diagnostics clean
```

- [ ] **Step 6: Commit the configuration change**

Run:

```bash
git add herdr/.config/herdr/config.toml
git commit -m "feat(herdr): bind prefix a to last tab"
```

Expected: commit succeeds and includes only `herdr/.config/herdr/config.toml`.

### Task 3: Manual verification instructions

**Files:**

- No modifications.

**Interfaces:**

- Consumes: Updated Herdr config from Task 2.
- Produces: Manual verification evidence that `prefix+a` changes tabs.

- [ ] **Step 1: Reload or restart Herdr**

Run the command you normally use to restart/reload Herdr after changing dotfiles. If using stow, apply the Herdr package first:

```bash
stow herdr
```

Then restart the Herdr client/server as appropriate for your setup.

Expected: Herdr starts without config errors.

- [ ] **Step 2: Verify previous-tab behavior manually**

In Herdr:

1. Open or focus Tab 1.
2. Focus Tab 2.
3. Press `prefix+a`.
4. Confirm focus returns to Tab 1.
5. Press `prefix+a` again.
6. Confirm focus returns to Tab 2.

Expected: `prefix+a` toggles between the current tab and the previously focused tab.

- [ ] **Step 3: Verify last-pane behavior is disabled**

In Herdr:

1. Focus Pane 1 in a tab.
2. Focus Pane 2 in the same tab.
3. Press `prefix+a`.

Expected: Herdr switches tabs according to previous-tab history. It does not focus the previously focused pane in the current tab.

- [ ] **Step 4: No commit needed**

No files changed in this task, so do not commit.
