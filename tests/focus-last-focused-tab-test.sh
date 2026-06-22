#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/herdr/.config/herdr/focus-last-focused-tab.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

TABS="$TMPDIR/tabs.json"
LOG="$TMPDIR/herdr-server.log"

cat >"$TABS" <<'JSON'
{"id":"cli:tab:list","result":{"type":"tab_list","tabs":[
  {"tab_id":"w1:t1","workspace_id":"w1","label":"one","number":1,"focused":false},
  {"tab_id":"w1:t2","workspace_id":"w1","label":"two","number":2,"focused":true},
  {"tab_id":"w1:t3","workspace_id":"w1","label":"three","number":3,"focused":false},
  {"tab_id":"w2:t1","workspace_id":"w2","label":"other","number":1,"focused":false}
]}}
JSON

cat >"$LOG" <<'LOG'
2026-06-22T18:22:55.798317Z INFO herdr::logging: tab focused event="tab.focus" subsystem="tab" outcome="ok" workspace_id="w1" tab_id="w1:t3"
2026-06-22T18:22:56.401564Z INFO herdr::logging: tab focused event="tab.focus" subsystem="tab" outcome="ok" workspace_id="w1" tab_id="w1:t2"
2026-06-22T18:22:57.180277Z INFO herdr::logging: tab focused event="tab.focus" subsystem="tab" outcome="ok" workspace_id="w1" tab_id="w1:t2"
LOG

assert_equals() {
	local expected="$1"
	local actual="$2"
	if [[ "$expected" != "$actual" ]]; then
		printf 'Expected:\n%s\n\nActual:\n%s\n' "$expected" "$actual" >&2
		exit 1
	fi
}

found="$(HERDR_LAST_TAB_TEST_MODE=find "$SCRIPT" "$TABS" "$LOG")"
assert_equals 'w1:t3' "$found"

focused="$(HERDR_LAST_TAB_TEST_MODE=focus HERDR_LAST_TAB_HERDR='printf "herdr %s %s %s\n" "$@"' "$SCRIPT" "$TABS" "$LOG")"
assert_equals 'herdr tab focus w1:t3' "$focused"

cat >>"$LOG" <<'LOG'
2026-06-22T18:22:58.841505Z INFO herdr::logging: tab focused event="tab.focus" subsystem="tab" outcome="ok" workspace_id="w9" tab_id="w9:closed"
LOG

found_after_closed="$(HERDR_LAST_TAB_TEST_MODE=find "$SCRIPT" "$TABS" "$LOG")"
assert_equals 'w1:t3' "$found_after_closed"

printf 'focus-last-focused-tab tests passed\n'
