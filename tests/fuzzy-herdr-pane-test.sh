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
  {"pane_id":"w2:p2","workspace_id":"w2","tab_id":"w2:t2","label":"agent"},
  {"pane_id":"w1:pTemp","workspace_id":"w1","tab_id":"w1:t1"}
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

format_output="$(HERDR_FUZZY_TEST_MODE=format HERDR_PANE_ID=w1:pTemp "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES")"
assert_contains "$format_output" $'personal / coding / pi\tw1:p1'
assert_contains "$format_output" $'personal / coding / pane w1:p2\tw1:p2'
assert_contains "$format_output" $'work / backend / agent\tw2:p1'
assert_contains "$format_output" $'work / backend / agent\tw2:p2'
if [[ "$format_output" == *'w1:pTemp'* ]]; then
	printf 'Expected temporary command pane w1:pTemp to be excluded:\n%s\n' "$format_output" >&2
	exit 1
fi

selected_output="$(HERDR_FUZZY_TEST_MODE=select HERDR_FUZZY_PICKER='printf "%s\n" "work / backend / agent	w2:p2"' HERDR_FUZZY_HERDR='printf "herdr %s %s %s %s\n" "$@"' "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES")"
assert_equals 'herdr pane current --pane w2:p2' "$selected_output"

cancel_output="$(HERDR_FUZZY_TEST_MODE=select HERDR_FUZZY_PICKER='sh -c "exit 130"' HERDR_FUZZY_HERDR='printf "should-not-run\n"' "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES")"
assert_equals '' "$cancel_output"

missing_picker_output="$(PATH=/usr/bin:/bin HERDR_FUZZY_TEST_MODE=missing-picker "$SCRIPT" "$WORKSPACES" "$TABS" "$PANES" 2>&1 || true)"
assert_contains "$missing_picker_output" 'Missing dependency: fzf'

printf 'fuzzy-herdr-pane tests passed\n'
