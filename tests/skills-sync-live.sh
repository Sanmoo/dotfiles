#!/usr/bin/env bash
# Live check of skills-sync against the real Skills CLI.
#
# Not part of the Quality gateway: it needs the network, and the runner
# discovers only tests/*-test.sh. Run it by hand after changing the script or
# the manifest:
#
#   bash tests/skills-sync-live.sh
#
# Everything happens in a throwaway HOME. The manifest is copied into a store
# directory and linked into that HOME, so the CLI rewrites the copy and never
# the tracked file in this checkout.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$ROOT_DIR/general/bin/skills-sync"
MANIFEST="$ROOT_DIR/skills-personal/skills-lock.json"
TMPDIR="$(mktemp -d)"
export HOME="$TMPDIR/home"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$HOME/.agents/skills" "$TMPDIR/store"
cp "$MANIFEST" "$TMPDIR/store/skills-lock.json"
ln -s "$TMPDIR/store/skills-lock.json" "$HOME/skills-lock.json"

# Stow provides both the manifest and the patch directory; this HOME is not
# stowed, so publish them the same way the package does.
cp -r "$ROOT_DIR/agents/.agents/skills-patches" "$HOME/.agents/skills-patches"

expected=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["skills"]))' "$MANIFEST")
sources=$(python3 -c 'import json,sys;print(len({s["source"] for s in json.load(open(sys.argv[1]))["skills"].values()}))' "$MANIFEST")

printf 'syncing %s skills from %s sources into %s\n' "$expected" "$sources" "$HOME"
"$SYNC" sync

installed=$(find "$HOME/.agents/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)
[[ "$installed" -eq "$expected" ]] || {
	printf 'FAIL: installed %s skills, expected %s\n' "$installed" "$expected" >&2
	exit 1
}

missing=$(python3 - "$MANIFEST" "$HOME/.agents/skills" <<'PY'
import json, os, sys
skills = json.load(open(sys.argv[1]))["skills"]
print(" ".join(n for n in skills if not os.path.isfile(os.path.join(sys.argv[2], n, "SKILL.md"))))
PY
)
[[ -z "$missing" ]] || {
	printf 'FAIL: no SKILL.md for: %s\n' "$missing" >&2
	exit 1
}

cmp -s "$TMPDIR/store/skills-lock.json" "$MANIFEST" || {
	printf 'FAIL: the CLI rewrote the manifest; review the diff before committing\n' >&2
	diff "$MANIFEST" "$TMPDIR/store/skills-lock.json" >&2 || true
	exit 1
}

grep -q 'disable-model-invocation: true' "$HOME/.agents/skills/harness-eval/SKILL.md" || {
	printf 'FAIL: the harness-eval patch was not reapplied after the install\n' >&2
	exit 1
}

# sync mirrors the upstream, so a file the upstream does not have must not survive.
mkdir -p "$HOME/.agents/skills/research/nested"
echo orphan >"$HOME/.agents/skills/research/ORPHAN.md"
echo orphan >"$HOME/.agents/skills/research/nested/ORPHAN2.md"
"$SYNC" sync
[[ ! -e "$HOME/.agents/skills/research/ORPHAN.md" && ! -e "$HOME/.agents/skills/research/nested/ORPHAN2.md" ]] || {
	printf 'FAIL: sync left an orphan file behind\n' >&2
	exit 1
}
[[ "$(grep -c 'disable-model-invocation' "$HOME/.agents/skills/harness-eval/SKILL.md")" == 1 ]] || {
	printf 'FAIL: the patch was duplicated on the second sync\n' >&2
	exit 1
}

printf 'PASS: skills-sync live (%s skills, %s sources)\n' "$expected" "$sources"
