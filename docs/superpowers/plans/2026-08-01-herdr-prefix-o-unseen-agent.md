# Herdr Prefix+O Unseen Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `prefix+o` focus the next Herdr agent whose status change has not been viewed yet, working reliably after toasts expire.

**Architecture:** Restore the custom `[[keys.command]]` binding for `prefix+o` pointing at a rewritten `focus-next-actionable-agent.sh`. The script reads `herdr agent list`, selects the first unseen actionable agent (`idle`/`blocked`/`done`) after the focused one (circular wrap) by comparing each agent's `state_change_seq` against a persistent JSON state file, focuses it, and records the sequence as viewed. Disable the native `open_notification_target`.

**Tech Stack:** bash, jq, herdr CLI (`agent list`, `agent focus`), TOML config, shell test suite with fake herdr binary.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-01-herdr-prefix-o-unseen-agent-design.md` (approved).
- Actionable statuses are exactly `idle`, `blocked`, `done`. `working` and non-agent panes are never candidates.
- Seen comparison normalizes `state_change_seq` with `// 0` on both sides: candidate iff `(seq // 0) != (seen[pane] // 0)`; an absent state entry means not viewed.
- State file is runtime data and MUST NOT be committed: add `herdr/.config/herdr/focus-state.json` to `.gitignore`.
- Env hooks: `HERDR_BIN_PATH` (default `herdr`), `HERDR_FOCUS_STATE_FILE` (default `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/focus-state.json`).
- No candidates → exit 0 silently, state file untouched.
- Pre-existing unrelated failure: `tests/http-oc-test.sh` FAILS on this machine. Do not fix it; the full-suite run must show all others PASS.
- Repo quirk: `docs/` is gitignored; new files under `docs/superpowers/` must be added with `git add -f`.

---

### Task 1: Script core with seen-state tracking

**Files:**

- Create: `herdr/.config/herdr/focus-next-actionable-agent.sh`
- Create: `tests/focus-next-actionable-agent-test.sh`

**Interfaces:**

- Consumes: herdr CLI `agent list` (JSON: `result.agents[].pane_id`, `.agent_status`, `.state_change_seq`, `.focused`, `.agent`) and `agent focus <pane_id>`; env `HERDR_BIN_PATH`, `HERDR_FOCUS_STATE_FILE`.
- Produces: `focus-next-actionable-agent.sh` exits 0 silently with no output when nothing to focus; prints nothing and writes `{"seen":{"<pane_id>":<seq>}}` to the state file when it focuses. Later tasks rely on these behaviors and env hooks.

- [ ] **Step 1: Write the failing test**

Create `tests/focus-next-actionable-agent-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/herdr/.config/herdr/focus-next-actionable-agent.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

FIXTURE="$TMPDIR/agents.json"
FOCUS_LOG="$TMPDIR/focus.log"
STATE="$TMPDIR/focus-state.json"
FAKE_HERDR="$TMPDIR/herdr"

cat >"$FAKE_HERDR" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
 agent)
  case "${2:-}" in
   list) cat "${FAKE_HERDR_AGENTS_FIXTURE:?}" ;;
   focus) printf '%s\n' "$3" >>"${FAKE_HERDR_FOCUS_LOG:?}" ;;
   *) exit 1 ;;
  esac
  ;;
 *) exit 1 ;;
esac
EOF
chmod +x "$FAKE_HERDR"

run() {
 HERDR_BIN_PATH="$FAKE_HERDR" \
 HERDR_FOCUS_STATE_FILE="$STATE" \
 FAKE_HERDR_AGENTS_FIXTURE="$FIXTURE" \
 FAKE_HERDR_FOCUS_LOG="$FOCUS_LOG" \
  "$SCRIPT"
}

assert_focus_log() {
 local expected="$1"
 local actual
 actual="$(cat "$FOCUS_LOG" 2>/dev/null || true)"
 if [[ "$actual" != "$expected" ]]; then
  printf 'Expected focus log:\n%s\n\nActual:\n%s\n' "$expected" "$actual" >&2
  exit 1
 fi
}

assert_state() {
 local expected="$1"
 local actual
 actual="$(cat "$STATE" 2>/dev/null || true)"
 if [[ "$actual" != "$expected" ]]; then
  printf 'Expected state:\n%s\n\nActual:\n%s\n' "$expected" "$actual" >&2
  exit 1
 fi
}

# Case 1: no agents -> nothing
cat >"$FIXTURE" <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list","agents":[]}}
JSON
run
assert_focus_log ''
assert_state ''

# Case 2: only working -> nothing
cat >"$FIXTURE" <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list","agents":[
  {"agent":"pi","pane_id":"w1:p1","agent_status":"working","state_change_seq":1,"focused":true,"cwd":"/a"}
]}}
JSON
run
assert_focus_log ''
assert_state ''

# Case 3: unseen idle agent -> focused and recorded
cat >"$FIXTURE" <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list","agents":[
  {"agent":"pi","pane_id":"w1:p1","agent_status":"idle","state_change_seq":6,"focused":false,"cwd":"/a"},
  {"agent":"pi","pane_id":"w1:p2","agent_status":"working","state_change_seq":102,"focused":true,"cwd":"/b"}
]}}
JSON
run
assert_focus_log 'w1:p1'
assert_state '{"seen":{"w1:p1":6}}'

# Case 4: already seen -> nothing
run
assert_focus_log 'w1:p1'
assert_state '{"seen":{"w1:p1":6}}'

# Case 5: state_change_seq bumped -> candidate again
cat >"$FIXTURE" <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list","agents":[
  {"agent":"pi","pane_id":"w1:p1","agent_status":"idle","state_change_seq":9,"focused":false,"cwd":"/a"},
  {"agent":"pi","pane_id":"w1:p2","agent_status":"working","state_change_seq":102,"focused":true,"cwd":"/b"}
]}}
JSON
run
assert_focus_log $'w1:p1\nw1:p1'
assert_state '{"seen":{"w1:p1":9}}'

printf 'focus-next-actionable-agent tests passed\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/focus-next-actionable-agent-test.sh`
Expected: FAIL — `No such file or directory` for the missing script (the fake `run()` cannot execute it).

- [ ] **Step 3: Write the script**

Create `herdr/.config/herdr/focus-next-actionable-agent.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

HERDR_BIN="${HERDR_BIN_PATH:-herdr}"
STATE_FILE="${HERDR_FOCUS_STATE_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/focus-state.json}"

need_cmd() {
 local cmd="$1"
 if ! command -v "$cmd" >/dev/null 2>&1; then
  printf 'Missing dependency: %s\n' "$cmd" >&2
  return 1
 fi
}

read_state() {
 local file="$1"
 if [[ ! -f "$file" ]]; then
  printf '{}'
  return 0
 fi
 jq -c '.' "$file"
}

write_state() {
 local file="$1"
 local dir
 dir="$(dirname "$file")"
 mkdir -p "$dir"
 printf '%s\n' "$2" >"$file.tmp"
 mv "$file.tmp" "$file"
}

main() {
 need_cmd jq

 local agents_json state result pane_id seq new_state
 agents_json="$("$HERDR_BIN" agent list)"
 state="$(read_state "$STATE_FILE")"

 result="$(jq -n -r \
  --argjson agents "$agents_json" \
  --argjson state "$state" \
  '
   ($agents.result.agents | to_entries) as $list
   | ($list | map(select(.value.focused == true)) | .[0].key // -1) as $focused_idx
   | [ $list[]
    | select(.value.agent != null)
    | select(.value.agent_status == "idle" or .value.agent_status == "blocked" or .value.agent_status == "done")
    | select((.value.state_change_seq // 0) != (($state.seen[.value.pane_id]) // 0))
   ] as $candidates
   | ($candidates | map(select(.key > $focused_idx)) | .[0]) as $after
   | (($after // $candidates[0]) // null)
   | if . == null then empty else [.value.pane_id, (.value.state_change_seq // 0)] | @tsv end
  ')"

 [[ -n "$result" ]] || return 0

 pane_id="${result%%$'\t'*}"
 seq="${result##*$'\t'}"

 "$HERDR_BIN" agent focus "$pane_id" >/dev/null

 new_state="$(jq -n -c \
  --argjson state "$state" \
  --arg pane "$pane_id" \
  --argjson seq "$seq" \
  '
   ($state.seen // {}) as $seen
   | $seen | .[$pane] = $seq
   | {seen: .}
  ')"
 write_state "$STATE_FILE" "$new_state"
}

main "$@"
```

- [ ] **Step 3b: Make the script executable**

Run: `chmod +x herdr/.config/herdr/focus-next-actionable-agent.sh` (repo convention: `git ls-files -s` shows `100755` for the other herdr scripts; `git add` records the mode).

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/focus-next-actionable-agent-test.sh`
Expected: PASS, prints `focus-next-actionable-agent tests passed`.

- [ ] **Step 5: Commit**

```bash
git add herdr/.config/herdr/focus-next-actionable-agent.sh tests/focus-next-actionable-agent-test.sh
git commit -m "feat: focus next unseen herdr agent with prefix+o"
```

---

### Task 2: Corrupt-state fallback and stale-pane pruning

**Files:**

- Modify: `herdr/.config/herdr/focus-next-actionable-agent.sh` (two spots: `read_state`, and the `new_state` jq block)
- Modify: `tests/focus-next-actionable-agent-test.sh` (append cases 6-9 before the final `printf`)

**Interfaces:**

- Consumes: Task 1 script, env hooks, fake herdr harness.
- Produces: `read_state` tolerates corrupt JSON (prints `{}`); the state write prunes `seen` entries whose pane is no longer in `agent list`; null `state_change_seq` recorded as `0`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/focus-next-actionable-agent-test.sh` just before the final `printf 'focus-next-actionable-agent tests passed\n'`:

```bash
# Case 6: circular order — advance after focused, wrap to first
cat >"$FIXTURE" <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list","agents":[
  {"agent":"pi","pane_id":"w1:p1","agent_status":"idle","state_change_seq":1,"focused":false,"cwd":"/a"},
  {"agent":"pi","pane_id":"w2:p2","agent_status":"working","state_change_seq":102,"focused":true,"cwd":"/b"},
  {"agent":"pi","pane_id":"w3:p3","agent_status":"done","state_change_seq":2,"focused":false,"cwd":"/c"},
  {"agent":"pi","pane_id":"w4:p4","agent_status":"idle","state_change_seq":3,"focused":false,"cwd":"/d"}
]}}
JSON
run
run
run
run
assert_focus_log $'w3:p3\nw4:p4\nw1:p1'
assert_state '{"seen":{"w3:p3":2,"w4:p4":3,"w1:p1":1}}'

# Wrap when focused agent is last in the list
cat >"$FIXTURE" <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list","agents":[
  {"agent":"pi","pane_id":"w1:p1","agent_status":"idle","state_change_seq":1,"focused":false,"cwd":"/a"},
  {"agent":"pi","pane_id":"w2:p2","agent_status":"idle","state_change_seq":2,"focused":false,"cwd":"/b"},
  {"agent":"pi","pane_id":"w3:p3","agent_status":"working","state_change_seq":102,"focused":true,"cwd":"/c"}
]}}
JSON
run
assert_focus_log $'w3:p3\nw4:p4\nw1:p1\nw1:p1'

# Case 7: corrupt state file -> treated as empty
printf 'not-json{{{\n' >"$STATE"
cat >"$FIXTURE" <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list","agents":[
  {"agent":"pi","pane_id":"w1:p1","agent_status":"idle","state_change_seq":6,"focused":false,"cwd":"/a"},
  {"agent":"pi","pane_id":"w1:p2","agent_status":"working","state_change_seq":102,"focused":true,"cwd":"/b"}
]}}
JSON
run
assert_focus_log $'w3:p3\nw4:p4\nw1:p1\nw1:p1\nw1:p1'
assert_state '{"seen":{"w1:p1":6}}'

# Case 8: panes gone from agent list -> their seen entries are pruned
printf '%s\n' '{"seen":{"w9:p9":5}}' >"$STATE"
run
assert_focus_log $'w3:p3\nw4:p4\nw1:p1\nw1:p1\nw1:p1\nw1:p1'
assert_state '{"seen":{"w1:p1":6}}'

# Case 9: null state_change_seq -> recorded as 0, not a candidate again
cat >"$FIXTURE" <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list","agents":[
  {"agent":"pi","pane_id":"w1:p1","agent_status":"idle","state_change_seq":null,"focused":false,"cwd":"/a"},
  {"agent":"pi","pane_id":"w1:p2","agent_status":"working","state_change_seq":102,"focused":true,"cwd":"/b"}
]}}
JSON
run
run
assert_focus_log $'w3:p3\nw4:p4\nw1:p1\nw1:p1\nw1:p1\nw1:p1\nw1:p1'
assert_state '{"seen":{"w1:p1":0}}'
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/focus-next-actionable-agent-test.sh`
Expected: FAIL — cases 6 passes (already implemented), but case 7 aborts the script (`read_state` runs `jq -c '.'` on corrupt JSON, jq exits non-zero, `set -e` kills the script), and case 8 fails because `w9:p9` is retained in the state file.

- [ ] **Step 3: Implement fallback and pruning**

In `herdr/.config/herdr/focus-next-actionable-agent.sh`, change `read_state` to tolerate corrupt JSON:

```bash
read_state() {
 local file="$1"
 if [[ ! -f "$file" ]]; then
  printf '{}'
  return 0
 fi
 jq -c '.' "$file" 2>/dev/null || printf '{}'
}
```

In `main()`, change the `new_state` computation to prune panes that no longer exist. Replace:

```bash
 new_state="$(jq -n -c \
  --argjson state "$state" \
  --arg pane "$pane_id" \
  --argjson seq "$seq" \
  '
   ($state.seen // {}) as $seen
   | $seen | .[$pane] = $seq
   | {seen: .}
  ')"
```

with:

```bash
 new_state="$(jq -n -c \
  --argjson agents "$agents_json" \
  --argjson state "$state" \
  --arg pane "$pane_id" \
  --argjson seq "$seq" \
  '
   (($state.seen // {}) | with_entries(select(.key as $k | ($agents.result.agents | map(.pane_id)) | index($k)))) as $seen
   | $seen | .[$pane] = $seq
   | {seen: .}
  ')"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/focus-next-actionable-agent-test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add herdr/.config/herdr/focus-next-actionable-agent.sh tests/focus-next-actionable-agent-test.sh
git commit -m "fix: tolerate corrupt herdr focus state and prune stale panes"
```

---

### Task 3: Config wiring, test update, gitignore

**Files:**

- Modify: `herdr/.config/herdr/config.toml`
- Modify: `tests/herdr-notification-target-test.sh` (rewrite)
- Modify: `.gitignore`
- Test: `tests/herdr-notification-target-test.sh`

**Interfaces:**

- Consumes: Task 1-2 script at `~/.config/herdr/focus-next-actionable-agent.sh` (path is the deployed symlink target; repo path is `herdr/.config/herdr/focus-next-actionable-agent.sh`).
- Produces: `prefix+o` bound via `[[keys.command]]`; `open_notification_target` disabled; state file ignored by git.

- [ ] **Step 1: Rewrite the failing config test**

Replace the entire contents of `tests/herdr-notification-target-test.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/herdr/.config/herdr/config.toml"

if grep -Eq '^open_notification_target = "prefix\+o"' "$CONFIG"; then
 printf 'Expected open_notification_target to be disabled for prefix+o\n' >&2
 exit 1
fi

if ! grep -Eq '^delivery = "herdr"' "$CONFIG"; then
 printf 'Expected in-app Herdr delivery so toasts stay visible\n' >&2
 exit 1
fi

if ! awk '
 /^\[\[keys\.command\]\]$/ { in_command = 1; block = $0 ORS; next }
 in_command && /^\[\[/ { if (block ~ /key = "prefix\+o"/) found = 1; in_command = 0 }
 in_command { block = block $0 ORS }
 END { if (in_command && block ~ /key = "prefix\+o"/) found = 1; exit found ? 0 : 1 }
' "$CONFIG"; then
 printf 'Expected custom keys.command binding for prefix+o\n' >&2
 exit 1
fi

if ! awk '
 /^\[\[keys\.command\]\]$/ { in_command = 1; block = $0 ORS; next }
 in_command && /^\[\[/ { if (block ~ /focus-next-actionable-agent\.sh/) found = 1; in_command = 0 }
 in_command { block = block $0 ORS }
 END { if (in_command && block ~ /focus-next-actionable-agent\.sh/) found = 1; exit found ? 0 : 1 }
' "$CONFIG"; then
 printf 'Expected prefix+o command to run focus-next-actionable-agent.sh\n' >&2
 exit 1
fi

printf 'herdr notification target tests passed\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/herdr-notification-target-test.sh`
Expected: FAIL — config still has `open_notification_target = "prefix+o"` and no `[[keys.command]]` block for `prefix+o`.

- [ ] **Step 3: Update the config**

In `herdr/.config/herdr/config.toml`, replace:

```toml
open_notification_target = "prefix+o" # jump to next pending notification target
```

with:

```toml
open_notification_target = "" # disabled; prefix+o is handled by focus-next-actionable-agent.sh
```

After the fuzzy pane `[[keys.command]]` block (the one with `key = "prefix+/"`), insert:

```toml
[[keys.command]]
key = "prefix+o"
type = "shell"
command = "~/.config/herdr/focus-next-actionable-agent.sh"
description = "focus next agent with unseen state change"
```

- [ ] **Step 4: Ignore the runtime state file**

In `.gitignore`, after the line `herdr/.config/herdr/session-history.json`, add:

```
herdr/.config/herdr/focus-state.json
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/herdr-notification-target-test.sh`
Expected: PASS, prints `herdr notification target tests passed`.

- [ ] **Step 6: Run the full suite**

Run:

```bash
for t in tests/*-test.sh; do printf '%-50s' "$t"; if bash "$t" >/tmp/test-out.log 2>&1; then echo PASS; else echo FAIL; tail -5 /tmp/test-out.log; fi; done
```

Expected: every test PASS except the pre-existing unrelated `tests/http-oc-test.sh` FAIL.

- [ ] **Step 7: Commit**

```bash
git add herdr/.config/herdr/config.toml tests/herdr-notification-target-test.sh .gitignore
git commit -m "feat: wire prefix+o to unseen-agent focus script"
```

- [ ] **Step 8: Manual smoke check (not automated)**

The live config is a symlink to the repo file (`~/.config/herdr/config.toml` → repo). Reload the running server and verify the shortcut:

```bash
herdr server reload-config
# press prefix+o: should focus the next idle/blocked/done agent with an unseen state change,
# even when no toast is showing; a second press with nothing new does nothing.
```
