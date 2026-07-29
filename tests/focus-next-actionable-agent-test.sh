#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/herdr/.config/herdr/focus-next-actionable-agent.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

HERDR_CALL_LOG="$TMPDIR/herdr.log"
HERDR_BIN_PATH="$TMPDIR/herdr"
HERDR_PANES_JSON="$TMPDIR/panes.json"

# Fake herdr: print panes JSON for "pane list", record all calls
cat >"$HERDR_BIN_PATH" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "herdr" "$*" >> "$HERDR_CALL_LOG"
case "$1 $2" in
  "pane list")
    cat "$HERDR_PANES_JSON"
    ;;
  "agent focus")
    exit 0
    ;;
esac
FAKE
chmod +x "$HERDR_BIN_PATH"

failures=0
failure_list=""

fail() {
	local label="$1"
	local detail="$2"
	failures=$((failures + 1))
	failure_list="${failure_list}  - ${label}: ${detail}"$'\n'
}

run_case() {
	local label="$1"
	local panes_json="$2"
	local expected="$3"
	printf '%s\n' "$panes_json" >"$HERDR_PANES_JSON"
	>"$HERDR_CALL_LOG"
	HERDR_BIN_PATH="$HERDR_BIN_PATH" HERDR_PANES_JSON="$HERDR_PANES_JSON" HERDR_CALL_LOG="$HERDR_CALL_LOG" \
		"$BASH" "$SCRIPT" 2>/dev/null || true
	local actual
	actual="$(cat "$HERDR_CALL_LOG" | xargs echo)"
	if [[ "$actual" != "$expected" ]]; then
		fail "$label" "expected call: $expected  actual call: $actual"
	fi
}

run_no_focus_case() {
	local label="$1"
	local panes_json="$2"
	printf '%s\n' "$panes_json" >"$HERDR_PANES_JSON"
	>"$HERDR_CALL_LOG"
	local exit_code=0
	HERDR_BIN_PATH="$HERDR_BIN_PATH" HERDR_PANES_JSON="$HERDR_PANES_JSON" HERDR_CALL_LOG="$HERDR_CALL_LOG" \
		"$BASH" "$SCRIPT" 2>/dev/null || exit_code=$?
	if [[ "$exit_code" -ne 0 ]]; then
		fail "$label" "expected exit 0, got $exit_code"
	fi
	if grep -Fq 'agent focus' "$HERDR_CALL_LOG"; then
		fail "$label" "expected no agent focus call, got: $(cat "$HERDR_CALL_LOG")"
	fi
}

# Cases
run_case 'idle-after-focused' '{"result":{"panes":[
  {"agent":"pi","agent_status":"working","focused":true,"terminal_id":"working"},
  {"agent":"pi","agent_status":"idle","focused":false,"terminal_id":"idle-target"}
]}}' 'herdr pane list herdr agent focus idle-target'

run_case 'wraps-after-last-candidate' '{"result":{"panes":[
  {"agent":"pi","agent_status":"idle","focused":false,"terminal_id":"first-idle"},
  {"agent":"pi","agent_status":"done","focused":false,"terminal_id":"done-target"},
  {"agent":"pi","agent_status":"working","focused":true,"terminal_id":"working"}
]}}' 'herdr pane list herdr agent focus first-idle'

run_case 'blocked-remains-actionable' '{"result":{"panes":[
  {"agent":"pi","agent_status":"working","focused":true,"terminal_id":"working"},
  {"agent":"pi","agent_status":"blocked","focused":false,"terminal_id":"blocked-target"}
]}}' 'herdr pane list herdr agent focus blocked-target'

run_case 'done-remains-actionable' '{"result":{"panes":[
  {"agent":"pi","agent_status":"working","focused":true,"terminal_id":"working"},
  {"agent":"pi","agent_status":"done","focused":false,"terminal_id":"done-target"}
]}}' 'herdr pane list herdr agent focus done-target'

run_no_focus_case 'excludes-working-and-non-agent' '{"result":{"panes":[
  {"agent":"pi","agent_status":"working","focused":true,"terminal_id":"working"},
  {"agent":"pi","agent_status":"working","focused":false,"terminal_id":"other-working"},
  {"agent_status":"idle","focused":false,"terminal_id":"not-agent"}
]}}'

# pane_id must be preferred over terminal_id when both exist
run_case 'prefers-pane-id' '{"result":{"panes":[
  {"agent":"pi","agent_status":"working","focused":true,"terminal_id":"working","pane_id":"w:p0"},
  {"agent":"pi","agent_status":"idle","focused":false,"terminal_id":"idle-term","pane_id":"w:p1"}
]}}' 'herdr pane list herdr agent focus w:p1'

if [[ "$failures" -gt 0 ]]; then
	printf 'FAILED (%d case(s)):\n%s' "$failures" "$failure_list" >&2
	exit 1
fi

printf 'focus-next-actionable-agent tests passed\n'
