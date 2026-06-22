#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
Usage:
  focus-last-focused-tab.sh
  HERDR_LAST_TAB_TEST_MODE=find focus-last-focused-tab.sh tabs.json herdr-server.log
  HERDR_LAST_TAB_TEST_MODE=focus focus-last-focused-tab.sh tabs.json herdr-server.log
EOF
}

need_cmd() {
	local cmd="$1"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		printf 'Missing dependency: %s\n' "$cmd" >&2
		return 1
	fi
}

current_tab_id() {
	local tabs_json="$1"
	jq -r '.result.tabs[] | select(.focused == true) | .tab_id' "$tabs_json" | head -n 1
}

tab_exists() {
	local tabs_json="$1"
	local tab_id="$2"
	jq -e --arg tab_id "$tab_id" '.result.tabs[] | select(.tab_id == $tab_id)' "$tabs_json" >/dev/null
}

last_focused_tab_id() {
	local tabs_json="$1"
	local log_file="$2"
	local current
	current="$(current_tab_id "$tabs_json")"

	if [[ -z "$current" ]]; then
		printf 'Could not determine current Herdr tab.\n' >&2
		return 1
	fi

	if [[ ! -f "$log_file" ]]; then
		printf 'Herdr log not found: %s\n' "$log_file" >&2
		return 1
	fi

	awk '
		/tab focused event="tab.focus"/ {
			if (match($0, /tab_id="[^"]+"/)) {
				value = substr($0, RSTART + 8, RLENGTH - 9)
				focused[++count] = value
			}
		}
		END {
			for (i = count; i >= 1; i--) {
				print focused[i]
			}
		}
	' "$log_file" | while IFS= read -r tab_id; do
		[[ -n "$tab_id" ]] || continue
		[[ "$tab_id" != "$current" ]] || continue
		if tab_exists "$tabs_json" "$tab_id"; then
			printf '%s\n' "$tab_id"
			return 0
		fi
	done | head -n 1
}

focus_tab() {
	local tab_id="$1"
	if [[ -n "${HERDR_LAST_TAB_HERDR:-}" ]]; then
		# Test hook. The command receives: tab focus <tab_id>
		bash -lc "$HERDR_LAST_TAB_HERDR" -- tab focus "$tab_id"
		return
	fi

	herdr tab focus "$tab_id" >/dev/null
}

load_live_tabs() {
	local out_file="$1"
	local herdr_cmd="${HERDR_LAST_TAB_HERDR_CMD:-herdr}"
	"$herdr_cmd" tab list >"$out_file"
}

run_with_files() {
	local tabs_json="$1"
	local log_file="$2"
	local tab_id
	tab_id="$(last_focused_tab_id "$tabs_json" "$log_file")"
	if [[ -z "$tab_id" ]]; then
		printf 'No previously focused Herdr tab found.\n' >&2
		return 1
	fi

	if [[ "${HERDR_LAST_TAB_TEST_MODE:-}" == "find" ]]; then
		printf '%s\n' "$tab_id"
		return 0
	fi

	focus_tab "$tab_id"
}

main() {
	local mode="${HERDR_LAST_TAB_TEST_MODE:-}"
	need_cmd jq

	if [[ "$mode" == "find" || "$mode" == "focus" ]]; then
		[[ $# -eq 2 ]] || {
			usage
			return 2
		}
		run_with_files "$1" "$2"
		return 0
	fi

	local tmpdir log_file
	tmpdir="$(mktemp -d)"
	trap "rm -rf '$tmpdir'" EXIT

	if ! load_live_tabs "$tmpdir/tabs.json"; then
		printf 'Could not read Herdr tabs via the Herdr CLI. Is the Herdr server running?\n' >&2
		return 1
	fi

	log_file="${HERDR_LAST_TAB_LOG:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/herdr-server.log}"
	run_with_files "$tmpdir/tabs.json" "$log_file"
}

main "$@"
