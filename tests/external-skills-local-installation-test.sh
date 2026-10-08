#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATE="$ROOT_DIR/general/bin/migrate-agent-skills"
APPLY="$ROOT_DIR/general/bin/apply-agent-config"
TMPDIR="$(mktemp -d)"
# Do not load the real home's Stow config or machine-specific Git hooks.
export HOME="$TMPDIR/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
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

# Real Stow refuses to stow a package tree that contains absolute symlinks, and
# a machine with external skills installed locally has gitignored absolute
# symlinks under agents/.agents/skills/ in the live checkout. Build a fixture
# containing only the repository's tracked content and apply from that, so the
# apply steps never see machine-local entries. The package-distribution checks
# below also read the fixture for the same reason: a live checkout can carry
# machine-local leftovers (for example an empty skills/<name>/ directory tree)
# that the package itself does not distribute. The assertion at the end still
# inspects the live checkout.
fixture="$TMPDIR/fixture-checkout"
mkdir -p "$fixture"
git -C "$ROOT_DIR" archive HEAD agents opencode | tar -x -C "$fixture"

# Applying the package to a new home creates a real shared directory and only
# links the repository-owned file into it.
"$APPLY" "$fixture" "$home"
assert_not_symlink "$home/.agents"
assert_file "$home/.agents/README.md"

# A dependency installed outside the repository survives reapplication and is
# not replaced by the package.
mkdir -p "$home/.agents/skills/vendor"
printf 'installed dependency\n' >"$home/.agents/skills/vendor/SKILL.md"
printf '{"local":true}\n' >"$home/.agents/.skill-lock.json"
"$APPLY" "$fixture" "$home"
assert_equals 'installed dependency' "$(<"$home/.agents/skills/vendor/SKILL.md")" \
	'local dependency remains unchanged'
assert_equals '{"local":true}' "$(<"$home/.agents/.skill-lock.json")" \
	'local installation metadata remains unchanged'

# Unexpected links must leave both the link and its target intact.
unexpected="$TMPDIR/unexpected-home"
mkdir -p "$unexpected/other" "$TMPDIR/expected-checkout/agents/.agents"
printf 'untouched\n' >"$unexpected/other/file"
ln -s "$unexpected/other" "$unexpected/.agents"
if "$MIGRATE" "$TMPDIR/expected-checkout" "$unexpected/.agents" >"$TMPDIR/unexpected.out" 2>&1; then
	printf 'FAIL: migration accepted an unexpected symlink\n' >&2
	exit 1
fi
[[ -L "$unexpected/.agents" ]] || { echo 'FAIL: unexpected link changed' >&2; exit 1; }
assert_equals 'untouched' "$(<"$unexpected/other/file")" 'unexpected target remains untouched'

# Migration copies the legacy checkout directory into the real global
# directory, preserving files, metadata, and links to unavailable targets.
legacy_home="$TMPDIR/legacy-home"
checkout="$TMPDIR/dotfiles"
mkdir -p "$legacy_home" "$checkout/agents/.agents/skills/vendor"
printf 'tracked skill\n' >"$checkout/agents/.agents/skills/vendor/SKILL.md"
printf 'local skill\n' >"$checkout/agents/.agents/skills/local.txt"
printf '{"installed":true}\n' >"$checkout/agents/.agents/.skill-lock.json"
ln -s /path/that/does/not/exist "$checkout/agents/.agents/skills/unavailable"
ln -s "$checkout/agents/.agents" "$legacy_home/.agents"

"$MIGRATE" "$checkout" "$legacy_home/.agents" --backup "$legacy_home/backup"
assert_not_symlink "$legacy_home/.agents"
assert_equals 'tracked skill' "$(<"$legacy_home/.agents/skills/vendor/SKILL.md")" \
	'migration preserves tracked files'
assert_equals 'local skill' "$(<"$legacy_home/.agents/skills/local.txt")" \
	'migration preserves local files'
assert_equals '{"installed":true}' "$(<"$legacy_home/.agents/.skill-lock.json")" \
	'migration preserves metadata'
assert_equals '/path/that/does/not/exist' "$(readlink "$legacy_home/.agents/skills/unavailable")" \
	'migration preserves symlink destinations'
assert_file "$checkout/agents/.agents/skills/vendor/SKILL.md"
assert_file "$legacy_home/backup/snapshot/skills/vendor/SKILL.md"

# Repeating a migration is a safe no-op.
"$MIGRATE" "$checkout" "$legacy_home/.agents"
assert_equals 'tracked skill' "$(<"$legacy_home/.agents/skills/vendor/SKILL.md")" \
	'repeated migration keeps the valid state'

# Existing destinations are rejected before changing either side.
conflict_home="$TMPDIR/conflict-home"
conflict_checkout="$TMPDIR/conflict-checkout"
mkdir -p "$conflict_home" "$conflict_checkout/agents/.agents" "$conflict_home/destination"
printf 'legacy\n' >"$conflict_checkout/agents/.agents/file"
ln -s "$conflict_checkout/agents/.agents" "$conflict_home/.agents"
if "$MIGRATE" "$conflict_checkout" "$conflict_home/.agents" --backup "$conflict_home/destination"; then
	printf 'FAIL: migration accepted a conflicting destination\n' >&2
	exit 1
fi
[[ -L "$conflict_home/.agents" ]] || {
	printf 'FAIL: conflict handling changed the legacy link\n' >&2
	exit 1
}
assert_file "$conflict_checkout/agents/.agents/file"

# Additional local source collisions are detected before creating a backup or
# modifying either source; adding another vendor creates no special exception.
extra_home="$TMPDIR/extra-conflict-home"
extra_checkout="$TMPDIR/extra-conflict-checkout"
extra_source="$TMPDIR/extra-source"
mkdir -p "$extra_home" "$extra_checkout/agents/.agents/skills/vendor" "$extra_source/vendor"
printf 'installed origin\n' >"$extra_checkout/agents/.agents/skills/vendor/SKILL.md"
printf 'conflicting origin\n' >"$extra_source/vendor/SKILL.md"
ln -s "$extra_checkout/agents/.agents" "$extra_home/.agents"
if "$MIGRATE" "$extra_checkout" "$extra_home/.agents" --backup "$extra_home/backup" --extra-skills "$extra_source" >"$TMPDIR/extra-conflict.out" 2>&1; then
	echo 'FAIL: conflicting additional source was accepted' >&2; exit 1
fi
[[ -L "$extra_home/.agents" && ! -e "$extra_home/backup" ]] || { echo 'FAIL: collision modified installation state' >&2; exit 1; }
assert_equals 'installed origin' "$(<"$extra_home/.agents/skills/vendor/SKILL.md")" 'existing origin remains intact'
assert_equals 'conflicting origin' "$(<"$extra_source/vendor/SKILL.md")" 'additional origin remains intact'

# Applying configuration refuses legacy/unexpected directory links instead of
# allowing Stow to write through them.
if "$APPLY" "$fixture" "$unexpected" >"$TMPDIR/apply-unexpected.out" 2>&1; then
	echo 'FAIL: application accepted a symlinked shared directory' >&2; exit 1
fi
assert_equals 'untouched' "$(<"$unexpected/other/file")" 'application does not follow the link'

# A broken global link or a regular file is not an already-migrated directory.
for state in broken file; do
	state_home="$TMPDIR/$state-home"
	mkdir "$state_home"
	if [[ "$state" == broken ]]; then
		ln -s "$TMPDIR/missing" "$state_home/.agents"
	else
		printf 'not a directory\n' >"$state_home/.agents"
	fi
	if "$MIGRATE" "$checkout" "$state_home/.agents" >"$TMPDIR/$state.out" 2>&1; then
		echo "FAIL: accepted $state state" >&2; exit 1
	fi
done

# Relative external links keep their target, even when unavailable. Absolute
# links into the legacy directory are rebased so removal cannot break them.
links_home="$TMPDIR/links-home"
links_checkout="$TMPDIR/links-checkout"
mkdir -p "$links_home" "$links_checkout/agents/.agents/skills/example" "$links_checkout/sources"
printf 'relative target\n' >"$links_checkout/sources/file"
printf 'internal file\n' >"$links_checkout/agents/.agents/skills/example/file"
ln -s ../../../../sources/file "$links_checkout/agents/.agents/skills/example/relative"
ln -s ../../../../sources/missing "$links_checkout/agents/.agents/skills/example/broken-relative"
ln -s "$links_checkout/agents/.agents/skills/example/file" "$links_checkout/agents/.agents/skills/example/absolute-internal"
ln -s file "$links_checkout/agents/.agents/skills/example/relative-internal"
mkdir -p "$links_home/external/deep"
printf 'correct external target\n' >"$links_home/external/choice"
printf 'wrong lexical target\n' >"$links_checkout/agents/.agents/skills/example/choice"
ln -s "$links_home/external/deep" "$links_checkout/agents/.agents/skills/example/hop"
ln -s hop/../choice "$links_checkout/agents/.agents/skills/example/through-hop"
ln -s ../../../../agents/.agents/skills/example/file "$links_checkout/agents/.agents/skills/example/reentry"
ln -s ../../../../sources/missing/../file "$links_checkout/agents/.agents/skills/example/missing-parent"
ln -s ../links-checkout/agents/.agents "$links_home/.agents"
"$MIGRATE" "$links_checkout" "$links_home/.agents" --backup "$links_home/backup"
assert_equals 'relative target' "$(<"$links_home/.agents/skills/example/relative")" 'relative external target is preserved'
assert_equals 'correct external target' "$(<"$links_home/.agents/skills/example/through-hop")" 'dot-dot is evaluated after following an intermediate symlink'
[[ ! -e "$links_home/.agents/skills/example/missing-parent" ]] || { echo 'FAIL: broken path became a different working target' >&2; exit 1; }
assert_equals 'file' "$(readlink "$links_home/.agents/skills/example/relative-internal")" 'relative internal text is preserved'
assert_equals '../../../../sources/missing' "$(readlink "$links_home/backup/snapshot/skills/example/broken-relative")" 'backup retains original relative link'
rm -rf "$links_checkout/agents/.agents"
assert_equals 'internal file' "$(<"$links_home/.agents/skills/example/absolute-internal")" 'internal link survives checkout removal'
assert_equals 'internal file' "$(<"$links_home/.agents/skills/example/reentry")" 'leave-and-reenter link survives checkout removal'

# A relative external hop must honor the intermediate symlink before '..'.
# The source symlink may be unavailable; the raw suffix must not be flattened.
printf 'wrong normalized target\n' >"$links_checkout/sources/choice"
ln -s "$links_home/external/deep" "$links_checkout/sources/hop"
# Exercise it in a fresh fixture so the complete transition runs again.
hop_home="$TMPDIR/hop-home"
hop_checkout="$TMPDIR/hop-checkout"
mkdir -p "$hop_home" "$hop_checkout/agents/.agents/skills/example"
ln -s "$links_checkout/sources/hop/../choice" "$hop_checkout/agents/.agents/skills/example/absolute-external"
ln -s "../../../../../links-checkout/sources/hop/../choice" "$hop_checkout/agents/.agents/skills/example/relative-external-hop"
ln -s "$hop_checkout/agents/.agents" "$hop_home/.agents"
"$MIGRATE" "$hop_checkout" "$hop_home/.agents" --backup "$hop_home/backup"
assert_equals 'correct external target' "$(<"$hop_home/.agents/skills/example/relative-external-hop")" 'external intermediate symlink is followed before dot-dot'
assert_equals "$links_checkout/sources/hop/../choice" "$(readlink "$hop_home/.agents/skills/example/absolute-external")" 'absolute external link text remains unchanged'

# A real OS write limit interrupts backup copying, before the legacy link is
# exchanged. No implementation hooks or real installations are used.
failure_home="$TMPDIR/failure-home"
failure_checkout="$TMPDIR/failure-checkout"
mkdir -p "$failure_home" "$failure_checkout/agents/.agents"
python3 - "$failure_checkout/agents/.agents/large" <<'PY'
import sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(b'x' * (1024 * 1024))
PY
ln -s "$failure_checkout/agents/.agents" "$failure_home/.agents"
if (ulimit -f 1; "$MIGRATE" "$failure_checkout" "$failure_home/.agents" --backup "$failure_home/backup") >"$TMPDIR/failure.out" 2>&1; then
	echo 'FAIL: write-limit failure was not exercised' >&2; exit 1
fi
[[ -L "$failure_home/.agents" ]] || { echo 'FAIL: failure removed legacy link' >&2; exit 1; }
assert_equals '1048576' "$(wc -c <"$failure_home/.agents/large" | tr -d ' ')" 'original installation survives copying failure'
"$MIGRATE" "$failure_checkout" "$failure_home/.agents" --backup "$failure_home/retry-backup"
assert_not_symlink "$failure_home/.agents"

# End-to-end Git transition: migrate local edits and untracked installations,
# normalize only the archived legacy package, then fast-forward its removal.
transition_home="$TMPDIR/transition-home"
transition_checkout="$TMPDIR/transition-checkout"
mkdir -p "$transition_home" "$transition_checkout/agents/.agents/skills/vendor" \
	"$transition_checkout/opencode/.config/opencode/skills/other-vendor"
printf 'another provider\n' >"$transition_checkout/opencode/.config/opencode/skills/other-vendor/SKILL.md"
ln -s /unavailable/other/provider "$transition_checkout/opencode/.config/opencode/skills/provider-link"
printf 'tracked upstream\n' >"$transition_checkout/agents/.agents/skills/vendor/SKILL.md"
printf '{}\n' >"$transition_checkout/agents/.agents/.skill-lock.json"
printf 'original settings\n' >"$transition_checkout/settings.txt"
git -C "$transition_checkout" -c init.templateDir= init -q -b main
git -C "$transition_checkout" config user.name 'Fixture User'
git -C "$transition_checkout" config user.email fixture@example.invalid
git -C "$transition_checkout" add .
git -C "$transition_checkout" commit -qm 'legacy fixture'
base=$(git -C "$transition_checkout" rev-parse HEAD)
git -C "$transition_checkout" checkout -qb separation
rm -rf "$transition_checkout/agents/.agents" "$transition_checkout/opencode/.config/opencode/skills"
mkdir -p "$transition_checkout/agents/.agents/skills/mine"
printf 'own skill\n' >"$transition_checkout/agents/.agents/skills/mine/SKILL.md"
git -C "$transition_checkout" add -A
git -C "$transition_checkout" commit -qm 'separate fixture dependencies'
git -C "$transition_checkout" checkout -q main
printf 'local tracked edit\n' >"$transition_checkout/agents/.agents/skills/vendor/SKILL.md"
printf 'unrelated settings\n' >"$transition_checkout/settings.txt"
mkdir -p "$transition_checkout/agents/.agents/skills/local"
printf 'untracked installation\n' >"$transition_checkout/agents/.agents/skills/local/SKILL.md"
ln -s /unavailable/fixture/provider "$transition_checkout/agents/.agents/skills/provider"
printf '{"chosen":"local"}\n' >"$transition_checkout/agents/.agents/.skill-lock.json"
ln -s "$transition_checkout/agents/.agents" "$transition_home/.agents"
"$MIGRATE" "$transition_checkout" "$transition_home/.agents" --backup "$transition_home/backup" \
	--extra-skills "$transition_checkout/opencode/.config/opencode/skills"
# Preserve the exact original package as well as the verified migration backup.
mv "$transition_checkout/agents/.agents" "$transition_home/backup/checkout-original"
git -C "$transition_checkout" restore --source=HEAD --worktree -- agents/.agents
git -C "$transition_checkout" merge -q --ff-only separation
assert_equals 'another provider' "$(<"$transition_home/.agents/skills/other-vendor/SKILL.md")" 'skills from another package survive removal'
assert_equals '/unavailable/other/provider' "$(readlink "$transition_home/.agents/skills/provider-link")" 'another package source link is preserved'
"$APPLY" "$transition_checkout" "$transition_home"
"$APPLY" "$transition_checkout" "$transition_home"
assert_equals 'local tracked edit' "$(<"$transition_home/.agents/skills/vendor/SKILL.md")" 'tracked local edit survives removal'
assert_equals 'untracked installation' "$(<"$transition_home/.agents/skills/local/SKILL.md")" 'untracked skill survives removal'
assert_equals '{"chosen":"local"}' "$(<"$transition_home/.agents/.skill-lock.json")" 'local lockfile survives removal'
assert_equals '/unavailable/fixture/provider' "$(readlink "$transition_home/.agents/skills/provider")" 'provider symlink survives removal'
assert_equals 'own skill' "$(<"$transition_home/.agents/skills/mine/SKILL.md")" 'owned skill is available individually'
assert_not_symlink "$transition_home/.agents/skills"
[[ -L "$transition_home/.agents/skills/mine/SKILL.md" ]] || { echo 'FAIL: owned file not linked' >&2; exit 1; }
git -C "$transition_checkout" merge-base --is-ancestor "$base" HEAD
assert_equals 'agents/.agents/skills/mine/SKILL.md' "$(git -C "$transition_checkout" ls-files agents/.agents)" 'only own skill is tracked'
assert_equals 'unrelated settings' "$(<"$transition_checkout/settings.txt")" 'unrelated configuration is untouched'
status_before=$(git -C "$transition_checkout" status --porcelain)
mkdir -p "$transition_home/.agents/skills/new-vendor"
printf 'new dependency\n' >"$transition_home/.agents/skills/new-vendor/SKILL.md"
printf '{"new":true}\n' >"$transition_home/.agents/.skill-lock.json"
assert_equals "$status_before" "$(git -C "$transition_checkout" status --porcelain)" 'new dependency does not change the checkout'

# Stow conflicts must not overwrite a local entry or apply other pending links.
rm "$transition_home/.agents/skills/mine/SKILL.md"
printf 'local conflict\n' >"$transition_home/.agents/skills/mine/SKILL.md"
printf 'second owned file\n' >"$transition_checkout/agents/.agents/skills/mine/EXTRA.md"
if "$APPLY" "$transition_checkout" "$transition_home" >"$TMPDIR/stow-conflict.out" 2>&1; then
	echo 'FAIL: application overwrote a local entry' >&2; exit 1
fi
assert_equals 'local conflict' "$(<"$transition_home/.agents/skills/mine/SKILL.md")" 'conflicting local file remains intact'
[[ ! -e "$transition_home/.agents/skills/mine/EXTRA.md" ]] || { echo 'FAIL: applied despite conflict' >&2; exit 1; }

# The current package must not distribute third-party skills even if patched.
assert_equals 'jira-issue-formatting' "$(find "$ROOT_DIR/agents/.agents/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)" 'only independently maintained authorship remains'
[[ ! -e "$ROOT_DIR/agents/.agents/.skill-lock.json" ]] || { echo 'FAIL: tracked installation lock remains' >&2; exit 1; }

for dependency in article-summarizer coding-guidelines docx ppt-master skill-architect; do
	path="$fixture/opencode/.config/opencode/skills/$dependency"
	[[ ! -e "$path" && ! -L "$path" ]] || { echo "FAIL: OpenCode still distributes $dependency" >&2; exit 1; }
done

printf 'external skills local installation tests passed\n'
