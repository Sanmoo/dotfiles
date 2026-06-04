#!/usr/bin/env bash
set -euo pipefail

HERDR_BIN="${HERDR_BIN_PATH:-herdr}"

json="$($HERDR_BIN pane list)"

target="$(jq -r '
  .result.panes as $panes
  | ([range(0; ($panes | length)) | select($panes[.].focused == true)][0] // -1) as $focused
  | ([range(0; ($panes | length))
      | select(($panes[.].agent // null) != null)
      | select(($panes[.].agent_status // "") as $s | $s == "blocked" or $s == "done")]) as $candidates
  | if ($candidates | length) == 0 then
      empty
    else
      (($candidates | map(select(. > $focused)) | .[0]) // $candidates[0]) as $idx
      | ($panes[$idx].terminal_id // $panes[$idx].pane_id)
    end
' <<<"$json")"

if [[ -z "${target:-}" ]]; then
	exit 0
fi

exec "$HERDR_BIN" agent focus "$target"
