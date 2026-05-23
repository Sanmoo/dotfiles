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
    printf '{"result":{"tab":{"tab_id":"workspace-1:99"}}}\n'
    ;;
  "agent start")
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
export TASK_REF="TASK-123"
export TASK_REPO_PATH="$tmpdir/repo"
export TASK_PROMPT_FILE="$tmpdir/prompt.txt"

"$repo_root/workq/.config/workq/launcher-herdr-pi.sh"

if ! grep -Fq 'herdr tab create --workspace workspace-1 --cwd ' "$HERDR_CALL_LOG"; then
	echo "expected launcher to create a new tab in the current workspace" >&2
	cat "$HERDR_CALL_LOG" >&2
	exit 1
fi

if ! grep -Fq 'herdr agent start workq:TASK-123 --cwd ' "$HERDR_CALL_LOG" ||
	! grep -Fq -- '--workspace workspace-1 --tab workspace-1:99 --focus -- pi Fix the thing' "$HERDR_CALL_LOG"; then
	echo "expected launcher to start pi in the newly created tab" >&2
	cat "$HERDR_CALL_LOG" >&2
	exit 1
fi
