# Herdr Fuzzy Pane Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Herdr's current `prefix+/` binding with a fuzzy picker that searches all panes by the concatenated `<workspace> / <tab> / <pane>` name and focuses the selected pane.

**Architecture:** Use Herdr's existing socket-backed CLI as the state and control interface. A small shell script calls `herdr workspace list`, `herdr tab list`, and `herdr pane list`, joins their JSON with `jq`, presents rows through `fzf`, and calls `herdr pane current --pane <pane_id>` for the selected pane. The Herdr config maps `prefix+/` to that script as an interactive temporary pane command.

**Tech Stack:** POSIX shell/bash, Herdr CLI, `jq`, `fzf`, TOML config, shell tests.

## Global Constraints

- The selectable items are always pane-level destinations.
- Search/display text must use the full concatenated name: `<workspace> / <tab> / <pane>`.
- `prefix+/` must no longer invoke the old non-fuzzy `goto` behavior.
- Do not modify AeroSpace or macOS workspace configuration.
- Use stable Herdr IDs for focus actions; display names are only for search/presentation.
- Canceling the picker must leave focus unchanged.
- The fallback script must not mutate Herdr session files directly.

---

## File Structure

- Modify `herdr/.config/herdr/config.toml`: remove/disable `goto = "prefix+/"`; add a `[[keys.command]]` for `prefix+/` that opens the fuzzy pane picker.
- Create `herdr/.config/herdr/fuzzy-herdr-pane.sh`: interactive script. It has testable helper modes for formatting and selection, plus normal mode for live Herdr/fzf use.
- Create `tests/fuzzy-herdr-pane-test.sh`: shell tests for formatting, duplicate names, cancel behavior, missing dependencies, and selected pane focus command generation.

The implementation intentionally uses the Herdr CLI because the installed Herdr exposes `workspace list`, `tab list`, `pane list`, and `pane current --pane ID`; no session-file mutation is needed.

---

### Task 1: Add tested fuzzy pane script

**Files:**

- Create: `herdr/.config/herdr/fuzzy-herdr-pane.sh`
- Create: `tests/fuzzy-herdr-pane-test.sh`

**Interfaces:**

- Consumes: Herdr CLI JSON from `herdr workspace list`, `herdr tab list`, `herdr pane list` in the shape `{ "result": { "workspaces": [...] } }`, `{ "result": { "tabs": [...] } }`, `{ "result": { "panes": [...] } }`.
- Produces: executable script `~/.config/herdr/fuzzy-herdr-pane.sh` with normal mode and test helper modes:
  - `HERDR_FUZZY_TEST_MODE=format ./fuzzy-herdr-pane.sh <workspaces.json> <tabs.json> <panes.json>` prints TSV rows: `<label>\t<pane_id>`.
  - `HERDR_FUZZY_TEST_MODE=select HERDR_FUZZY_PICKER='command...' HERDR_FUZZY_HERDR='command...' ./fuzzy-herdr-pane.sh <workspaces.json> <tabs.json> <panes.json>` prints or executes the resulting focus command path without requiring live Herdr.

- [ ] **Step 1: Write the failing test**

Create `tests/fuzzy-herdr-pane-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/herdr/.config/herdr/fuzzy-herdr-pane.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

WORKSPACES="$TMPDIR/workspaces.json"
TABS="$TMPDIR/tabs.json"
PANES="$TMPDIR/panes.json"

cat >"$WORKSPACES" <<'JSON'
{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[
  {"workspace_id":"w1","label":"personal","number":1},
  {"workspace_id":"w2","label":"work","number":2}
]}}
JSON

cat >"$TABS" <<'JSON'
{"id":"cli:tab:list","result":{"type":"tab_list","tabs":[
  {"tab_id":"w1:t1","workspace_id":"w1","label":"coding","number":1},
  {"tab_id":"w2:t1","workspace_id":"w2","label":"backend","number":1},
  {"tab_id":"w2:t2","workspace_id":"w2","label":"backend","number":2}
]}}
JSON

cat >"$PANES" <<'JSON'
{"id":"cli:pane:list","result":{"type":"pane_list","panes":[
  {"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","label":"pi"},
  {"pane_id":"w1:p2","workspace_id":"w1","tab_id":"w1:t1"},
  {"pane_id":"w2:p1","workspace_id":"w2","tab_id":"w2:t1","label":"agent"},
  {"pane_id":"w2:p2","workspace_id":"w2","tab_id":"w2:t2","label":"agent"}
]}}
JSON

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected output to contain:\n%s\n\nActual output:\n%s\n' "$needle" "$haystack" >&2
    exit 1
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    printf 'Expected:\n%s\n\nActual:\n%s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

format_output="$(HERDR_FUZZY_TEST_MODE=format "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES")"
assert_contains "$format_output" $'personal / coding / pi\tw1:p1'
assert_contains "$format_output" $'personal / coding / pane w1:p2\tw1:p2'
assert_contains "$format_output" $'work / backend / agent\tw2:p1'
assert_contains "$format_output" $'work / backend / agent\tw2:p2'

selected_output="$(HERDR_FUZZY_TEST_MODE=select HERDR_FUZZY_PICKER='printf "%s\n" "work / backend / agent w2:p2"' HERDR_FUZZY_HERDR='printf "herdr %s %s %s\n"' "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES")"
assert_equals 'herdr pane current --pane w2:p2' "$selected_output"

cancel_output="$(HERDR_FUZZY_TEST_MODE=select HERDR_FUZZY_PICKER='sh -c "exit 130"' HERDR_FUZZY_HERDR='printf "should-not-run\n"' "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES")"
assert_equals '' "$cancel_output"

missing_picker_output="$(PATH=/usr/bin:/bin HERDR_FUZZY_TEST_MODE=missing-picker "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES" 2>&1 || true)"
assert_contains "$missing_picker_output" 'Missing dependency: fzf'

printf 'fuzzy-herdr-pane tests passed\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/fuzzy-herdr-pane-test.sh
```

Expected: FAIL because `herdr/.config/herdr/fuzzy-herdr-pane.sh` does not exist or is not executable.

- [ ] **Step 3: Write minimal implementation**

Create `herdr/.config/herdr/fuzzy-herdr-pane.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  fuzzy-herdr-pane.sh
  HERDR_FUZZY_TEST_MODE=format fuzzy-herdr-pane.sh workspaces.json tabs.json panes.json
  HERDR_FUZZY_TEST_MODE=select fuzzy-herdr-pane.sh workspaces.json tabs.json panes.json
EOF
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Missing dependency: %s\n' "$cmd" >&2
    return 1
  fi
}

load_live_json() {
  local out_dir="$1"
  local herdr_cmd="${HERDR_FUZZY_HERDR_CMD:-herdr}"

  "$herdr_cmd" workspace list >"$out_dir/workspaces.json"
  "$herdr_cmd" tab list >"$out_dir/tabs.json"
  "$herdr_cmd" pane list >"$out_dir/panes.json"
}

format_rows() {
  local workspaces_json="$1"
  local tabs_json="$2"
  local panes_json="$3"

  jq -r -s '
    def workspace_label($id):
      (.[0].result.workspaces[] | select(.workspace_id == $id) | .label) // $id;
    def tab_label($id):
      (.[1].result.tabs[] | select(.tab_id == $id) | .label) // $id;
    .[2].result.panes[]
    | [
        ((workspace_label(.workspace_id)) + " / " + (tab_label(.tab_id)) + " / " + (.label // ("pane " + .pane_id))),
        .pane_id
      ]
    | @tsv
  ' "$workspaces_json" "$tabs_json" "$panes_json"
}

pick_row() {
  local picker_cmd="${HERDR_FUZZY_PICKER:-fzf --prompt='Herdr pane> ' --with-nth=1 --delimiter=$'\t'}"
  bash -lc "$picker_cmd"
}

focus_pane() {
  local pane_id="$1"
  if [[ -n "${HERDR_FUZZY_HERDR:-}" ]]; then
    # Test hook. The command receives: pane current --pane <pane_id>
    bash -lc "$HERDR_FUZZY_HERDR" -- pane current --pane "$pane_id"
  else
    herdr pane current --pane "$pane_id"
  fi
}

run_with_files() {
  local workspaces_json="$1"
  local tabs_json="$2"
  local panes_json="$3"

  local rows selected pane_id
  rows="$(format_rows "$workspaces_json" "$tabs_json" "$panes_json")"
  if [[ -z "$rows" ]]; then
    printf 'No Herdr panes found.\n' >&2
    return 1
  fi

  selected="$(printf '%s\n' "$rows" | pick_row || true)"
  if [[ -z "$selected" ]]; then
    return 0
  fi

  pane_id="${selected##*$'\t'}"
  if [[ -z "$pane_id" || "$pane_id" == "$selected" ]]; then
    printf 'Could not determine selected pane id.\n' >&2
    return 1
  fi

  focus_pane "$pane_id"
}

main() {
  local mode="${HERDR_FUZZY_TEST_MODE:-}"

  need_cmd jq

  if [[ "$mode" == "missing-picker" ]]; then
    need_cmd fzf
    return 0
  fi

  if [[ "$mode" == "format" ]]; then
    [[ $# -eq 3 ]] || { usage; return 2; }
    format_rows "$1" "$2" "$3"
    return 0
  fi

  if [[ "$mode" == "select" ]]; then
    [[ $# -eq 3 ]] || { usage; return 2; }
    run_with_files "$1" "$2" "$3"
    return 0
  fi

  need_cmd fzf

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  if ! load_live_json "$tmpdir"; then
    printf 'Could not read Herdr state via the Herdr CLI. Is the Herdr server running?\n' >&2
    return 1
  fi

  run_with_files "$tmpdir/workspaces.json" "$tmpdir/tabs.json" "$tmpdir/panes.json"
}

main "$@"
```

Make it executable:

```bash
chmod +x herdr/.config/herdr/fuzzy-herdr-pane.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
bash tests/fuzzy-herdr-pane-test.sh
```

Expected: PASS and prints `fuzzy-herdr-pane tests passed`.

- [ ] **Step 5: Manually smoke-test formatting against live Herdr CLI**

Run:

```bash
tmpdir="$(mktemp -d)"
herdr workspace list >"$tmpdir/workspaces.json"
herdr tab list >"$tmpdir/tabs.json"
herdr pane list >"$tmpdir/panes.json"
HERDR_FUZZY_TEST_MODE=format herdr/.config/herdr/fuzzy-herdr-pane.sh "$tmpdir/workspaces.json" "$tmpdir/tabs.json" "$tmpdir/panes.json" | head -10
rm -rf "$tmpdir"
```

Expected: rows like `dotfiles / dotfiles / agent<TAB>w653426f2f822d5:p2`.

- [ ] **Step 6: Commit**

```bash
git add herdr/.config/herdr/fuzzy-herdr-pane.sh tests/fuzzy-herdr-pane-test.sh
git commit -m "feat(herdr): add fuzzy pane picker script"
```

---

### Task 2: Bind `prefix+/` to the fuzzy pane picker

**Files:**

- Modify: `herdr/.config/herdr/config.toml`

**Interfaces:**

- Consumes: executable script `~/.config/herdr/fuzzy-herdr-pane.sh` from Task 1.
- Produces: Herdr keybinding where `prefix+/` runs the fuzzy picker instead of the old `goto` action.

- [ ] **Step 1: Write the failing config check**

Run:

```bash
if grep -q '^goto = "prefix+/"' herdr/.config/herdr/config.toml; then
  echo 'FAIL: old goto binding is still active'
  exit 1
fi
```

Expected: FAIL and prints `FAIL: old goto binding is still active`.

- [ ] **Step 2: Update `config.toml`**

In `herdr/.config/herdr/config.toml`, replace:

```toml
goto = "prefix+/"       # open pane/panel search
```

with:

```toml
# prefix+/ is remapped below to a fuzzy pane picker over workspace / tab / pane.
# goto = "prefix+/"     # open pane/panel search
```

Then add this command block after the existing `prefix+o` command block:

```toml
[[keys.command]]
key = "prefix+/"
type = "pane"
command = "~/.config/herdr/fuzzy-herdr-pane.sh"
description = "fuzzy focus pane by workspace/tab/pane"
```

- [ ] **Step 3: Run config checks**

Run:

```bash
if grep -q '^goto = "prefix+/"' herdr/.config/herdr/config.toml; then
  echo 'FAIL: old goto binding is still active'
  exit 1
fi

grep -A4 -n 'key = "prefix+/"' herdr/.config/herdr/config.toml
```

Expected: no FAIL, and output includes:

```text
key = "prefix+/"
type = "pane"
command = "~/.config/herdr/fuzzy-herdr-pane.sh"
description = "fuzzy focus pane by workspace/tab/pane"
```

- [ ] **Step 4: Run Herdr config validation by reload**

Run:

```bash
HERDR_CONFIG_PATH="$PWD/herdr/.config/herdr/config.toml" herdr server reload-config
```

Expected: command exits 0. If Herdr does not honor `HERDR_CONFIG_PATH` for reload, run `herdr server reload-config` after stowing or copying the config manually.

- [ ] **Step 5: Run script tests again**

Run:

```bash
bash tests/fuzzy-herdr-pane-test.sh
```

Expected: PASS and prints `fuzzy-herdr-pane tests passed`.

- [ ] **Step 6: Commit**

```bash
git add herdr/.config/herdr/config.toml
git commit -m "feat(herdr): bind prefix slash to fuzzy pane picker"
```

---

### Task 3: Final live verification and documentation note

**Files:**

- Modify: `docs/superpowers/plans/2026-06-22-herdr-fuzzy-pane-navigation.md` only if verification notes are added before final commit; otherwise no code/config files.

**Interfaces:**

- Consumes: script and config from Tasks 1-2.
- Produces: verified working Herdr shortcut in the developer environment.

- [ ] **Step 1: Verify dependencies**

Run:

```bash
command -v herdr
command -v jq
command -v fzf
```

Expected: each command prints an executable path.

- [ ] **Step 2: Verify live picker can open**

Run:

```bash
herdr/.config/herdr/fuzzy-herdr-pane.sh
```

Expected: `fzf` opens with entries in the format `<workspace> / <tab> / <pane>`. Press Esc. Expected: command exits without focusing a pane and without error.

- [ ] **Step 3: Verify live focus behavior**

Run:

```bash
herdr/.config/herdr/fuzzy-herdr-pane.sh
```

Select a pane that is not currently focused. Expected: Herdr focuses that pane by calling `herdr pane current --pane <pane_id>`.

- [ ] **Step 4: Verify keybinding behavior in Herdr**

Inside an active Herdr client, press:

```text
ctrl+a
/
```

Expected: the fuzzy picker opens in a temporary pane. Select a target. Expected: the target pane becomes focused. Repeat and press Esc. Expected: focus remains unchanged.

- [ ] **Step 5: Check final git state**

Run:

```bash
git status --short
```

Expected: no unexpected changes besides any intentionally uncommitted user files that existed before this work, currently known as:

```text
 M git/.gitconfig
 M pi-mac/.pi/agent/settings.json
```

- [ ] **Step 6: Final commit if verification notes changed**

If any documentation or verification note was added, commit it:

```bash
git add docs/superpowers/plans/2026-06-22-herdr-fuzzy-pane-navigation.md
git commit -m "docs: record herdr fuzzy pane verification"
```

If no files changed, skip this commit.
