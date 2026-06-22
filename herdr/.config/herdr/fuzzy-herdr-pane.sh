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
    . as $docs
    | def workspace_label($id):
        ($docs[0].result.workspaces[] | select(.workspace_id == $id) | .label) // $id;
      def tab_label($id):
        ($docs[1].result.tabs[] | select(.tab_id == $id) | .label) // $id;
      $docs[2].result.panes[]
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
		[[ $# -eq 3 ]] || {
			usage
			return 2
		}
		format_rows "$1" "$2" "$3"
		return 0
	fi

	if [[ "$mode" == "select" ]]; then
		[[ $# -eq 3 ]] || {
			usage
			return 2
		}
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
