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
