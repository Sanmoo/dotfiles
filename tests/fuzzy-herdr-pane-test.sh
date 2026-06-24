#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/herdr/.config/herdr/fuzzy-herdr-pane.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

WORKSPACES="$TMPDIR/workspaces.json"
TABS="$TMPDIR/tabs.json"
PANES="$TMPDIR/panes.json"
LOG="$TMPDIR/herdr-server.log"

cat >"$WORKSPACES" <<'JSON'
{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[
  {"workspace_id":"w1","label":"personal","number":1},
  {"workspace_id":"w2","label":"work","number":2}
]}}
JSON

cat >"$TABS" <<'JSON'
{"id":"cli:tab:list","result":{"type":"tab_list","tabs":[
  {"tab_id":"w1:t1","workspace_id":"w1","label":"coding","number":1,"focused":false},
  {"tab_id":"w2:t1","workspace_id":"w2","label":"backend","number":1,"focused":true},
  {"tab_id":"w2:t2","workspace_id":"w2","label":"backend","number":2,"focused":false}
]}}
JSON

cat >"$PANES" <<'JSON'
{"id":"cli:pane:list","result":{"type":"pane_list","panes":[
  {"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","label":"pi"},
  {"pane_id":"w1:p2","workspace_id":"w1","tab_id":"w1:t1"},
  {"pane_id":"w2:p1","workspace_id":"w2","tab_id":"w2:t1","label":"agent"},
  {"pane_id":"w2:p2","workspace_id":"w2","tab_id":"w2:t2","label":"agent"},
  {"pane_id":"w1:pTemp","workspace_id":"w1","tab_id":"w1:t1","label":""}
]}}
JSON

cat >"$LOG" <<'LOG'
2026-06-22T18:22:55.798317Z INFO herdr::logging: tab focused event="tab.focus" subsystem="tab" outcome="ok" workspace_id="w1" tab_id="w1:t1"
2026-06-22T18:22:56.401564Z INFO herdr::logging: tab focused event="tab.focus" subsystem="tab" outcome="ok" workspace_id="w2" tab_id="w2:t2"
2026-06-22T18:22:57.180277Z INFO herdr::logging: tab focused event="tab.focus" subsystem="tab" outcome="ok" workspace_id="w2" tab_id="w2:t1"
LOG

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

format_output="$(HERDR_FUZZY_TEST_MODE=format HERDR_PANE_ID=w2:p1 "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES" "$LOG")"
expected_format_output=$'work / backend / agent\tw2:p2\npersonal / coding / pi\tw1:p1\npersonal / coding\tw1:p2\npersonal / coding\tw1:pTemp'
assert_equals "$expected_format_output" "$format_output"
if [[ "$format_output" == *$'work / backend / agent\tw2:p1'* ]]; then
	printf 'Expected current focused tab w2:t1 to be excluded:\n%s\n' "$format_output" >&2
	exit 1
fi

selected_output="$(HERDR_FUZZY_TEST_MODE=select HERDR_FUZZY_PICKER='printf "%s\n" "work / backend / agent	w2:p2"' HERDR_FUZZY_HERDR='printf "herdr %s %s %s %s\n" "$@"' "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES")"
assert_equals 'herdr pane current --pane w2:p2' "$selected_output"

cancel_output="$(HERDR_FUZZY_TEST_MODE=select HERDR_FUZZY_PICKER='sh -c "exit 130"' HERDR_FUZZY_HERDR='printf "should-not-run\n"' "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES")"
assert_equals '' "$cancel_output"

STUB_BIN="$TMPDIR/bin"
mkdir -p "$STUB_BIN"
ln -s "$(command -v jq)" "$STUB_BIN/jq"
missing_picker_output="$(PATH="$STUB_BIN" HERDR_FUZZY_TEST_MODE=missing-picker "$BASH" "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES" 2>&1 || true)"
assert_contains "$missing_picker_output" 'Missing dependency: fzf'

printf 'fuzzy-herdr-pane tests passed\n'
