#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
export HOME="$TMPDIR/home"
trap 'rm -rf "$TMPDIR"' EXIT

assert_equals() {
	local expected="$1" actual="$2" message="$3"
	if [[ "$expected" != "$actual" ]]; then
		printf 'FAIL: %s\nexpected: %s\nactual: %s\n' "$message" "$expected" "$actual" >&2
		exit 1
	fi
}

assert_contains() {
	local haystack="$1" needle="$2" message="$3"
	if [[ "$haystack" != *"$needle"* ]]; then
		printf 'FAIL: %s\nmissing: %s\nin: %s\n' "$message" "$needle" "$haystack" >&2
		exit 1
	fi
}

# Run a command, capturing combined output and status, without tripping set -e.
run_capture() {
	set +e
	OUT=$("$@" 2>&1)
	STATUS=$?
	set -e
}

# A stub stands in for the Skills CLI: it records its arguments and, crucially,
# drains stdin the way the real npx does. Without that second behaviour the
# manifest loop's stdin-consumption regression would not be caught here.
mkdir -p "$TMPDIR/bin" "$HOME/.agents/skills"
cat >"$TMPDIR/bin/npx" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NPX_LOG"
cat >/dev/null
STUB
chmod +x "$TMPDIR/bin/npx"
export PATH="$TMPDIR/bin:$PATH"
export NPX_LOG="$TMPDIR/npx.log"
: >"$NPX_LOG"

# Two profile manifests in a fixture checkout, with the applied profile linked
# into $HOME exactly as Stow would link it.
profile_dir="$TMPDIR/checkout"
mkdir -p "$profile_dir/skills-personal" "$profile_dir/skills-corporate"
cat >"$profile_dir/skills-personal/skills-lock.json" <<'JSON'
{
  "version": 1,
  "skills": {
    "zeta": { "source": "owner/repo-b", "sourceType": "github", "skillPath": "b/zeta/SKILL.md", "computedHash": "x" },
    "alpha": { "source": "owner/repo-a", "sourceType": "github", "skillPath": "a/alpha/SKILL.md", "computedHash": "x" },
    "beta": { "source": "owner/repo-a", "sourceType": "github", "skillPath": "a/beta/SKILL.md", "computedHash": "x" }
  }
}
JSON
cat >"$profile_dir/skills-corporate/skills-lock.json" <<'JSON'
{
  "version": 1,
  "skills": {
    "zeta": { "source": "org/fork-b", "sourceType": "github", "skillPath": "b/zeta/SKILL.md", "computedHash": "y" }
  }
}
JSON
ln -s "$profile_dir/skills-personal/skills-lock.json" "$HOME/skills-lock.json"

# Exercise the script through the shape it has on a machine: a Stow symlink under
# ~/bin pointing into the checkout. The patches are read from the checkout, so
# this fixture checkout — not the real one — has to supply them.
mkdir -p "$profile_dir/general/bin" "$profile_dir/skills-patches"
cp "$ROOT_DIR/general/bin/skills-sync" "$profile_dir/general/bin/skills-sync"
chmod +x "$profile_dir/general/bin/skills-sync"
ln -s "$profile_dir/general/bin/skills-sync" "$TMPDIR/bin/skills-sync"
SYNC="$TMPDIR/bin/skills-sync"

# sources: one line per source, both sorted.
expected_sources=$'owner/repo-a\talpha beta\nowner/repo-b\tzeta'
assert_equals "$expected_sources" "$("$SYNC" sources)" 'sources groups by source and sorts'

# sync: every source in the manifest is replayed, in order.
run_capture "$SYNC" sync
assert_equals '0' "$STATUS" 'sync exits 0'
assert_equals '2' "$(wc -l <"$NPX_LOG" | tr -d ' ')" 'sync runs one add per source'
add_first=$(sed -n 1p "$NPX_LOG")
add_second=$(sed -n 2p "$NPX_LOG")
assert_contains "$add_first" 'add owner/repo-a -s alpha beta' 'first add carries its own skills'
assert_contains "$add_second" 'add owner/repo-b -s zeta' 'second add survives the loop stdin'
assert_contains "$("$SYNC" --help)" 'Usage: skills-sync' 'help prints usage'

# patches: applied inside the frontmatter, once, and idempotently.
mkdir -p "$HOME/.agents/skills/alpha"
cat >"$HOME/.agents/skills/alpha/SKILL.md" <<'MD'
---
name: alpha
description: "d"
---
# Alpha

A body rule follows.

---

End.
MD
printf 'disable-model-invocation: true\n' >"$profile_dir/skills-patches/alpha.txt"
"$SYNC" patches >/dev/null
assert_equals '4:disable-model-invocation: true' "$(grep -n 'disable-model-invocation' "$HOME/.agents/skills/alpha/SKILL.md")" \
	'patch lands in the frontmatter, not the body'
assert_equals '1' "$(grep -c 'disable-model-invocation' "$HOME/.agents/skills/alpha/SKILL.md")" 'patch applied once'
before=$(cat "$HOME/.agents/skills/alpha/SKILL.md")
"$SYNC" patches >/dev/null
assert_equals "$before" "$(cat "$HOME/.agents/skills/alpha/SKILL.md")" 'patches are idempotent'

# patches: a missing skill and a file without frontmatter are both survivable.
printf 'disable-model-invocation: true\n' >"$profile_dir/skills-patches/absent.txt"
run_capture "$SYNC" patches
assert_equals '0' "$STATUS" 'a patch for a missing skill does not fail'
assert_contains "$OUT" 'skipping patch, skill not installed: absent' 'a missing skill is reported'
mkdir -p "$HOME/.agents/skills/beta"
printf '# no frontmatter\n' >"$HOME/.agents/skills/beta/SKILL.md"
printf 'disable-model-invocation: true\n' >"$profile_dir/skills-patches/beta.txt"
run_capture "$SYNC" patches
assert_equals '0' "$STATUS" 'a file without frontmatter does not fail'
assert_equals '# no frontmatter' "$(cat "$HOME/.agents/skills/beta/SKILL.md")" 'a file without frontmatter is left alone'

# patches: without the directory the script says so instead of failing silently.
mv "$profile_dir/skills-patches" "$profile_dir/skills-patches.off"
run_capture "$SYNC" patches
assert_equals '0' "$STATUS" 'a missing patches directory does not fail'
assert_contains "$OUT" 'no patches directory at' 'a missing patches directory is reported'
mv "$profile_dir/skills-patches.off" "$profile_dir/skills-patches"

# diff: reports the profile differences and exits 1 when they differ.
run_capture "$SYNC" diff
assert_equals '1' "$STATUS" 'diff exits 1 when the profiles differ'
assert_contains "$OUT" 'only in skills-personal (2): alpha beta' 'diff lists skills missing from the sibling'
assert_contains "$OUT" 'different source: zeta: owner/repo-b != org/fork-b' 'diff reports a diverging source'

# diff: a matching sibling exits 0.
cp "$profile_dir/skills-personal/skills-lock.json" "$profile_dir/skills-corporate/skills-lock.json"
run_capture "$SYNC" diff
assert_equals '0' "$STATUS" 'diff exits 0 when the profiles match'

# diff: a manifest that is not a Stow link cannot be compared.
rm "$HOME/skills-lock.json"
printf '{ "version": 1, "skills": {} }\n' >"$HOME/skills-lock.json"
run_capture "$SYNC" diff
assert_equals '1' "$STATUS" 'diff refuses a manifest that is not a link'
assert_contains "$OUT" 'diff needs an applied profile package' 'diff explains why'

# State errors and usage errors are distinguishable.
run_capture "$SYNC" sources
assert_equals '0' "$STATUS" 'an empty but present manifest is fine'
rm "$HOME/skills-lock.json"
run_capture "$SYNC" sync
assert_equals '1' "$STATUS" 'a missing manifest is a state error'
assert_contains "$OUT" 'no manifest at' 'the missing manifest is named'
run_capture "$SYNC" frobnicate
assert_equals '2' "$STATUS" 'an unknown command is a usage error'
run_capture "$SYNC" add owner/repo-a -s alpha -g
assert_equals '1' "$STATUS" 'a global add is refused'
assert_contains "$OUT" 'does not enter the tracked manifest' 'the refusal explains itself'

printf 'PASS: skills-sync\n'
