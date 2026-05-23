#!/usr/bin/env bash
set -euo pipefail

if ! command -v herdr >/dev/null 2>&1; then
	echo "herdr not found in PATH" >&2
	exit 127
fi
if ! command -v jq >/dev/null 2>&1; then
	echo "jq not found in PATH" >&2
	exit 127
fi
if ! command -v pi >/dev/null 2>&1; then
	echo "pi not found in PATH" >&2
	exit 127
fi

if [[ -z "${TASK_REF:-}" || -z "${TASK_REPO_PATH:-}" || -z "${TASK_PROMPT_FILE:-}" ]]; then
	echo "WorkQ task environment is incomplete" >&2
	exit 2
fi

workspace_id=""
if [[ -n "${HERDR_PANE_ID:-}" ]]; then
	workspace_id="$(herdr pane get "$HERDR_PANE_ID" | jq -r '.result.pane.workspace_id // empty')"
fi

if [[ -z "$workspace_id" ]]; then
	workspace_id="$(herdr workspace list | jq -r '.result.workspaces[] | select(.focused == true) | .workspace_id' | head -n1)"
fi

if [[ -z "$workspace_id" ]]; then
	echo "Could not determine Herdr workspace for launcher" >&2
	exit 2
fi

prompt="$(cat "$TASK_PROMPT_FILE")"
label="$TASK_REF"

tab_json="$(herdr tab create \
	--workspace "$workspace_id" \
	--cwd "$TASK_REPO_PATH" \
	--label "$label" \
	--focus)"

pane_id="$(jq -r '.result.root_pane.pane_id // empty' <<<"$tab_json")"

if [[ -z "$pane_id" ]]; then
	echo "Could not create Herdr tab root pane for launcher" >&2
	exit 2
fi

printf -v quoted_prompt '%q' "$prompt"
exec herdr pane run "$pane_id" "exec pi $quoted_prompt"
