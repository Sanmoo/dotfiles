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
	local exclude_pane_id="${HERDR_PANE_ID:-}"

	jq -r -s --arg exclude_pane_id "$exclude_pane_id" '
    . as $docs
    | def workspace_label($id):
        ($docs[0].result.workspaces[] | select(.workspace_id == $id) | .label) // $id;
      def tab_label($id):
        ($docs[1].result.tabs[] | select(.tab_id == $id) | .label) // $id;
      $docs[2].result.panes[]
      | select(.pane_id != $exclude_pane_id)
      | [
          ((workspace_label(.workspace_id)) + " / " + (tab_label(.tab_id)) + " / " + (.label // ("pane " + .pane_id))),
          .pane_id
        ]
      | @tsv
  ' "$workspaces_json" "$tabs_json" "$panes_json"
}

pick_row() {
	if [[ -n "${HERDR_FUZZY_PICKER:-}" ]]; then
		bash -lc "$HERDR_FUZZY_PICKER"
	else
		fzf --prompt='Herdr pane> ' --with-nth=1 --delimiter=$'\t'
	fi
}

focus_direction_to_target() {
	local current_pane_id="$1"
	local target_pane_id="$2"

	herdr pane layout --pane "$target_pane_id" | jq -r \
		--arg current "$current_pane_id" \
		--arg target "$target_pane_id" '
    .result.layout.panes as $panes
    | ($panes[] | select(.pane_id == $current) | .rect) as $current_rect
    | ($panes[] | select(.pane_id == $target) | .rect) as $target_rect
    | (($current_rect.x + ($current_rect.width / 2)) - ($target_rect.x + ($target_rect.width / 2))) as $dx
    | (($current_rect.y + ($current_rect.height / 2)) - ($target_rect.y + ($target_rect.height / 2))) as $dy
    | if (($dx | fabs) > ($dy | fabs)) then
        if $dx > 0 then "left" else "right" end
      else
        if $dy > 0 then "up" else "down" end
      end
  '
}

focused_pane_in_tab() {
	local tab_id="$1"
	herdr pane list | jq -r --arg tab_id "$tab_id" '
    .result.panes[]
    | select(.tab_id == $tab_id and .focused == true)
    | .pane_id
  ' | head -n 1
}

focus_pane() {
	local pane_id="$1"
	if [[ -n "${HERDR_FUZZY_HERDR:-}" ]]; then
		# Test hook. The command receives: pane current --pane <pane_id>
		bash -lc "$HERDR_FUZZY_HERDR" -- pane current --pane "$pane_id"
		return
	fi

	local pane_json tab_id current_pane_id direction
	pane_json="$(herdr pane get "$pane_id")"
	tab_id="$(printf '%s\n' "$pane_json" | jq -r '.result.pane.tab_id')"

	herdr tab focus "$tab_id" >/dev/null

	for _ in 1 2 3 4 5 6 7 8 9 10; do
		current_pane_id="$(focused_pane_in_tab "$tab_id")"
		if [[ "$current_pane_id" == "$pane_id" ]]; then
			return 0
		fi
		if [[ -z "$current_pane_id" ]]; then
			printf 'Could not determine focused pane in tab %s.\n' "$tab_id" >&2
			return 1
		fi

		direction="$(focus_direction_to_target "$current_pane_id" "$pane_id")"
		if [[ -z "$direction" || "$direction" == "null" ]]; then
			printf 'Could not determine direction from %s to %s.\n' "$current_pane_id" "$pane_id" >&2
			return 1
		fi

		herdr pane focus --direction "$direction" --pane "$current_pane_id" >/dev/null
	done

	printf 'Could not focus pane %s after navigation attempts.\n' "$pane_id" >&2
	return 1
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
	trap "rm -rf '$tmpdir'" EXIT

	if ! load_live_json "$tmpdir"; then
		printf 'Could not read Herdr state via the Herdr CLI. Is the Herdr server running?\n' >&2
		return 1
	fi

	run_with_files "$tmpdir/workspaces.json" "$tmpdir/tabs.json" "$tmpdir/panes.json"
}

main "$@"
