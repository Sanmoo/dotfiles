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
