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

# Case 6: circular order — advance after focused, wrap to first
: >"$FOCUS_LOG"
rm -f "$STATE"
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
assert_focus_log $'w3:p3\nw4:p4\nw1:p1\nw2:p2'

# Case 7: corrupt state file -> treated as empty
printf 'not-json{{{\n' >"$STATE"
cat >"$FIXTURE" <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list","agents":[
  {"agent":"pi","pane_id":"w1:p1","agent_status":"idle","state_change_seq":6,"focused":false,"cwd":"/a"},
  {"agent":"pi","pane_id":"w1:p2","agent_status":"working","state_change_seq":102,"focused":true,"cwd":"/b"}
]}}
JSON
run
assert_focus_log $'w3:p3\nw4:p4\nw1:p1\nw2:p2\nw1:p1'
assert_state '{"seen":{"w1:p1":6}}'

# Case 8: panes gone from agent list -> their seen entries are pruned
printf '%s\n' '{"seen":{"w9:p9":5}}' >"$STATE"
run
assert_focus_log $'w3:p3\nw4:p4\nw1:p1\nw2:p2\nw1:p1\nw1:p1'
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
assert_focus_log $'w3:p3\nw4:p4\nw1:p1\nw2:p2\nw1:p1\nw1:p1\nw1:p1'
assert_state '{"seen":{"w1:p1":0}}'

printf 'focus-next-actionable-agent tests passed\n'
