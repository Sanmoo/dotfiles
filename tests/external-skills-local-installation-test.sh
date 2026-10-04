#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATE="$ROOT_DIR/general/bin/migrate-agent-skills"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_equals() {
	local expected="$1" actual="$2" message="$3"
	if [[ "$expected" != "$actual" ]]; then
		printf 'FAIL: %s\nexpected: %s\nactual: %s\n' "$message" "$expected" "$actual" >&2
		exit 1
	fi
}

assert_file() {
	[[ -f "$1" ]] || { printf 'FAIL: expected file %s\n' "$1" >&2; exit 1; }
}

assert_not_symlink() {
	[[ ! -L "$1" ]] || { printf 'FAIL: expected real directory %s\n' "$1" >&2; exit 1; }
}

home="$TMPDIR/home"
mkdir -p "$home"

# Applying the package to a new home creates a real shared directory and only
# links the repository-owned file into it.
stow --no-folding -d "$ROOT_DIR" -t "$home" agents
assert_not_symlink "$home/.agents"
assert_file "$home/.agents/README.md"

# A dependency installed outside the repository survives reapplication and is
# not replaced by the package.
mkdir -p "$home/.agents/skills/vendor"
printf 'installed dependency\n' >"$home/.agents/skills/vendor/SKILL.md"
printf '{"local":true}\n' >"$home/.agents/.skill-lock.json"
stow --no-folding -d "$ROOT_DIR" -t "$home" agents
assert_equals 'installed dependency' "$(<"$home/.agents/skills/vendor/SKILL.md")" \
	'local dependency remains unchanged'
assert_equals '{"local":true}' "$(<"$home/.agents/.skill-lock.json")" \
	'local installation metadata remains unchanged'

# Migration moves the legacy checkout directory into the real global
# directory, preserving files, metadata, and links to unavailable targets.
legacy_home="$TMPDIR/legacy-home"
checkout="$TMPDIR/dotfiles"
mkdir -p "$legacy_home" "$checkout/agents/.agents/skills/vendor"
printf 'tracked skill\n' >"$checkout/agents/.agents/skills/vendor/SKILL.md"
printf 'local skill\n' >"$checkout/agents/.agents/skills/local.txt"
printf '{"installed":true}\n' >"$checkout/agents/.agents/.skill-lock.json"
ln -s /path/that/does/not/exist "$checkout/agents/.agents/skills/unavailable"
ln -s "$checkout/agents/.agents" "$legacy_home/.agents"

"$MIGRATE" "$legacy_home/.agents"
assert_not_symlink "$legacy_home/.agents"
assert_equals 'tracked skill' "$(<"$legacy_home/.agents/skills/vendor/SKILL.md")" \
	'migration preserves tracked files'
assert_equals 'local skill' "$(<"$legacy_home/.agents/skills/local.txt")" \
	'migration preserves local files'
assert_equals '{"installed":true}' "$(<"$legacy_home/.agents/.skill-lock.json")" \
	'migration preserves metadata'
assert_equals '/path/that/does/not/exist' "$(readlink "$legacy_home/.agents/skills/unavailable")" \
	'migration preserves symlink destinations'
[[ ! -e "$checkout/agents/.agents" ]] || {
	printf 'FAIL: migration left the legacy checkout directory in place\n' >&2
	exit 1
}

# Repeating a migration is a safe no-op.
"$MIGRATE" "$legacy_home/.agents"
assert_equals 'tracked skill' "$(<"$legacy_home/.agents/skills/vendor/SKILL.md")" \
	'repeated migration keeps the valid state'

# Existing destinations are rejected before changing either side.
conflict_home="$TMPDIR/conflict-home"
conflict_checkout="$TMPDIR/conflict-checkout"
mkdir -p "$conflict_home" "$conflict_checkout/agents/.agents" "$conflict_home/destination"
printf 'legacy\n' >"$conflict_checkout/agents/.agents/file"
ln -s "$conflict_checkout/agents/.agents" "$conflict_home/.agents"
if "$MIGRATE" "$conflict_home/.agents" "$conflict_home/destination"; then
	printf 'FAIL: migration accepted a conflicting destination\n' >&2
	exit 1
fi
[[ -L "$conflict_home/.agents" ]] || {
	printf 'FAIL: conflict handling changed the legacy link\n' >&2
	exit 1
}
assert_file "$conflict_checkout/agents/.agents/file"

printf 'external skills local installation tests passed\n'
