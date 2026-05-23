#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/repo"
printf 'Fix the thing' >"$tmpdir/prompt.txt"

cat >"$tmpdir/bin/herdr" <<'HERDR'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "herdr $*" >> "$HERDR_CALL_LOG"
case "$1 $2" in
  "pane get")
    printf '{"result":{"pane":{"workspace_id":"workspace-1"}}}\n'
    ;;
  "tab create")
    printf '{"result":{"root_pane":{"pane_id":"pane-99"},"tab":{"tab_id":"workspace-1:99"}}}\n'
    ;;
  "pane run")
    exit 0
    ;;
  *)
    printf 'unexpected herdr call: %s\n' "$*" >&2
    exit 1
    ;;
esac
HERDR
chmod +x "$tmpdir/bin/herdr"

cat >"$tmpdir/bin/pi" <<'PI'
#!/usr/bin/env bash
exit 0
PI
chmod +x "$tmpdir/bin/pi"

export PATH="$tmpdir/bin:$PATH"
export HERDR_CALL_LOG="$tmpdir/herdr.log"
export HERDR_PANE_ID="pane-1"
export TASK_REF="workq:TASK-123"
export TASK_REPO_PATH="$tmpdir/repo"
export TASK_PROMPT_FILE="$tmpdir/prompt.txt"

"$repo_root/workq/.config/workq/launcher-herdr-pi.sh"

if ! grep -Fq 'herdr tab create --workspace workspace-1 --cwd ' "$HERDR_CALL_LOG" ||
	! grep -Fq -- '--label workq:TASK-123 --focus' "$HERDR_CALL_LOG"; then
	echo "expected launcher to create and focus a new tab in the current workspace" >&2
	cat "$HERDR_CALL_LOG" >&2
	exit 1
fi

if grep -Fq -- '--label workq:workq:TASK-123' "$HERDR_CALL_LOG"; then
	echo "expected launcher not to duplicate the workq prefix in the tab label" >&2
	cat "$HERDR_CALL_LOG" >&2
	exit 1
fi

if grep -Fq 'herdr agent start' "$HERDR_CALL_LOG"; then
	echo "expected launcher not to create a second agent pane" >&2
	cat "$HERDR_CALL_LOG" >&2
	exit 1
fi

if ! grep -Fq 'herdr pane run pane-99 exec pi Fix\ the\ thing' "$HERDR_CALL_LOG"; then
	echo "expected launcher to run pi in the new tab's root pane" >&2
	cat "$HERDR_CALL_LOG" >&2
	exit 1
fi
