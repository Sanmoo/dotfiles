#!/usr/bin/env bash
# tier: slow
# Tests for the sandbox entrypoint at its external boundaries.
#
# The entrypoint converges the declared environment with `mise` and the sandbox
# package tree with `npm ci`, puts the declared shims ahead of the image's
# binaries, checks Pi's Node engine requirement, and then runs the command. This harness runs the real script
# with stubs for `mise`, `pi`, and `npm` on a controlled PATH and asserts on
# the calls, environment, ordering, and exit codes it produces. No Docker
# daemon is required.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="$repo_root/safe-pi/entrypoint.sh"
bash_bin="$(command -v bash)"
tmpdir="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

# The image's binaries live in one directory on PATH after the shims. Stubs
# for mise, pi, and npm stand in for them; node is the real one, so the engine
# check exercises a real runtime against a real semver implementation.
IMAGE_BIN="$tmpdir/image-bin"
mkdir -p "$IMAGE_BIN"
# The entrypoint serializes convergence with flock, which util-linux provides on
# Linux and a Homebrew package does on macOS. run_entrypoint keeps only
# $IMAGE_BIN on PATH, so expose the host's flock there rather than assume it.
flock_bin="$(command -v flock || true)"
[[ -n "$flock_bin" ]] || fail "flock is required to run the entrypoint test"
ln -sf "$flock_bin" "$IMAGE_BIN/flock"
CALL_LOG="$tmpdir/calls.log"
: >"$CALL_LOG"

# The probe (`--dry-run-code`) exits 1 when a tool is missing and 0 when
# nothing is; the install step exits with SAFE_PI_FAKE_MISE_STATUS.
cat >"$IMAGE_BIN/mise" <<'MISE'
#!/usr/bin/env bash
set -euo pipefail
log="${SAFE_PI_TEST_LOG:?}"
if [[ " $* " == *" --dry-run-code "* ]]; then
	printf 'mise probe cwd=%s\n' "$PWD" >>"$log"
	if [[ "${SAFE_PI_FAKE_MISE_MISSING:-1}" == "1" ]]; then
		exit 1
	fi
	printf 'mise all tools are installed\n'
	exit 0
fi
printf 'mise-begin\n' >>"$log"
printf 'mise %s cwd=%s trusted=%s data=%s cache=%s state=%s precompiled=%s compile=%s lang=%s\n' "$*" "$PWD" \
	"${MISE_TRUSTED_CONFIG_PATHS-}" "${MISE_DATA_DIR-}" \
	"${MISE_CACHE_DIR-}" "${MISE_STATE_DIR-}" \
	"${MISE_ERLANG_PRECOMPILED_OS-}" "${MISE_ERLANG_COMPILE-}" "${LANG-}" >>"$log"
sleep "${SAFE_PI_FAKE_MISE_SLEEP:-0}"
printf 'mise-end\n' >>"$log"
if [[ -n "${SAFE_PI_FAKE_MISE_FAIL_CWD-}" && "$PWD" == "$SAFE_PI_FAKE_MISE_FAIL_CWD" ]]; then
	exit 3
fi
exit "${SAFE_PI_FAKE_MISE_STATUS:-0}"
MISE
chmod +x "$IMAGE_BIN/mise"

cat >"$IMAGE_BIN/npm" <<'NPM'
#!/usr/bin/env bash
set -euo pipefail
printf 'npm %s\n' "$*" >>"${SAFE_PI_TEST_LOG:?}"
if [[ "${1-} ${2-}" == "root -g" ]]; then
	printf '%s\n' "${SAFE_PI_TEST_NPM_ROOT:?}"
	exit 0
fi
if [[ "${1-}" == "ci" ]]; then
	# The package tree install: record where and with what, leave a marker the
	# tests can see, and exit with the scripted status.
	printf 'npm-ci-begin cwd=%s path=%s\n' "$PWD" "$PATH" >>"$SAFE_PI_TEST_LOG"
	sleep "${SAFE_PI_FAKE_NPM_CI_SLEEP:-0}"
	printf 'npm-ci-end\n' >>"$SAFE_PI_TEST_LOG"
	printf 'npm-ci-output\n'
	[[ "${SAFE_PI_FAKE_NPM_CI_STATUS:-0}" == "0" ]] || exit "$SAFE_PI_FAKE_NPM_CI_STATUS"
	mkdir -p node_modules
	exit 0
fi
exit 99
NPM
chmod +x "$IMAGE_BIN/npm"

cat >"$IMAGE_BIN/locale" <<'LOCALE'
#!/usr/bin/env bash
set -euo pipefail
# The image's available locales, so the run does not depend on the host's.
if [[ "${1-}" == "-a" ]]; then
	printf '%s\n' ${SAFE_PI_FAKE_LOCALES:?}
	exit 0
fi
exit 99
LOCALE
chmod +x "$IMAGE_BIN/locale"

cat >"$IMAGE_BIN/pi" <<'PI'
#!/usr/bin/env bash
set -euo pipefail
printf 'pi %s\n' "$*" >>"${SAFE_PI_TEST_LOG:?}"
printf 'pi-path %s\n' "$PATH" >>"$SAFE_PI_TEST_LOG"
exit "${SAFE_PI_FAKE_PI_STATUS:-0}"
PI
chmod +x "$IMAGE_BIN/pi"

# The real node, except that the Node ABI the key is built from can be scripted:
# the image's Node major cannot be swapped in a test.
real_node="$(command -v node)"
cat >"$IMAGE_BIN/node" <<NODE
#!/usr/bin/env bash
if [[ "\$*" == "-p process.versions.modules" && -n "\${SAFE_PI_FAKE_NODE_ABI-}" ]]; then
	printf '%s\n' "\$SAFE_PI_FAKE_NODE_ABI"
	exit 0
fi
exec "$real_node" "\$@"
NODE
chmod +x "$IMAGE_BIN/node"

# Pi's engine check reads npm's bundled semver. Locate the host's copy so the
# test uses the real range logic rather than a double.
host_semver="$(npm root -g)/npm/node_modules/semver"
[[ -f "$host_semver/package.json" ]] || fail "cannot locate npm's bundled semver at $host_semver"

# make_npm_root DIR RANGE: a global npm root holding a Pi package whose engine
# requirement is RANGE, plus the semver module npm bundles.
make_npm_root() {
	local dir="$1" range="$2"
	mkdir -p "$dir/@earendil-works/pi-coding-agent" "$dir/npm/node_modules"
	ln -sfn "$host_semver" "$dir/npm/node_modules/semver"
	printf '{"name":"@earendil-works/pi-coding-agent","version":"1.1.0","engines":{"node":"%s"}}\n' \
		"$range" >"$dir/@earendil-works/pi-coding-agent/package.json"
}

npm_ok="$tmpdir/npm-ok"
npm_unsatisfied="$tmpdir/npm-unsatisfied"
npm_no_pi="$tmpdir/npm-no-pi"
make_npm_root "$npm_ok" ">=22.19.0"
make_npm_root "$npm_unsatisfied" ">=99.0.0"
mkdir -p "$npm_no_pi"

data="$tmpdir/mise-data"
home="$tmpdir/home"
host_npm="$tmpdir/host-npm"
sandbox_npm="$home/.pi/agent/npm"
workdir="$tmpdir/repo"
mkdir -p "$home" "$workdir"

reset_stubs() {
	: >"$CALL_LOG"
	rm -rf "$data" "$host_npm" "$home/.pi"
	mkdir -p "$data"
	FAKE_NODE_ABI=127
	FAKE_NPM_CI_STATUS=0
	FAKE_NPM_CI_SLEEP=0
	npm_root="$npm_ok"
	FAKE_MISE_STATUS=0
	FAKE_MISE_SLEEP=0
	FAKE_PI_STATUS=0
	FAKE_INHERITED_TRUST=""
	FAKE_MISE_FAIL_CWD=""
	FAKE_MISE_MISSING=1
	FAKE_LOCALES="C.utf8 en_US.utf8 POSIX"
	FAKE_LOCALE_LANG="en_US.UTF-8"
	FAKE_LOCALE_LC_ALL=""
	FAKE_LOCALE_LC_CTYPE="en_US.UTF-8"
}

# run_entrypoint [--cwd DIR] [entrypoint args...]
# Runs the real entrypoint with the stubs first on PATH, after a bare
# environment so host settings cannot leak into the assertions.
run_entrypoint() {
	local cwd="$workdir"
	if [[ "${1-}" == "--cwd" ]]; then
		cwd="$2"
		shift 2
	fi
	(
		cd "$cwd"
		env -i \
			HOME="$home" \
			PATH="$IMAGE_BIN:/usr/bin:/bin" \
			LANG="$FAKE_LOCALE_LANG" \
			LC_ALL="$FAKE_LOCALE_LC_ALL" \
			LC_CTYPE="$FAKE_LOCALE_LC_CTYPE" \
			MISE_DATA_DIR="$data" \
			MISE_TRUSTED_CONFIG_PATHS="$FAKE_INHERITED_TRUST" \
			SAFE_PI_FAKE_LOCALES="$FAKE_LOCALES" \
			SAFE_PI_TEST_LOG="$CALL_LOG" \
			SAFE_PI_TEST_NPM_ROOT="$npm_root" \
			SAFE_PI_FAKE_MISE_STATUS="$FAKE_MISE_STATUS" \
			SAFE_PI_FAKE_MISE_SLEEP="$FAKE_MISE_SLEEP" \
			SAFE_PI_FAKE_MISE_FAIL_CWD="$FAKE_MISE_FAIL_CWD" \
			SAFE_PI_FAKE_MISE_MISSING="$FAKE_MISE_MISSING" \
			SAFE_PI_FAKE_PI_STATUS="$FAKE_PI_STATUS" \
			SAFE_PI_HOST_NPM_DIR="$host_npm" \
			SAFE_PI_FAKE_NODE_ABI="$FAKE_NODE_ABI" \
			SAFE_PI_FAKE_NPM_CI_STATUS="$FAKE_NPM_CI_STATUS" \
			SAFE_PI_FAKE_NPM_CI_SLEEP="$FAKE_NPM_CI_SLEEP" \
			"$bash_bin" "$ENTRYPOINT" "$@"
	)
}

# status_of COMMAND...: prints the command's exit status without tripping set -e.
status_of() {
	local status
	set +e
	"$@"
	status=$?
	set -e
	printf '%s' "$status"
}

assert_call() {
	grep -Fq -- "$1" "$CALL_LOG" || {
		printf 'call log:\n' >&2
		cat "$CALL_LOG" >&2
		fail "expected call log to contain: $1"
	}
}

assert_no_call() {
	! grep -Fq -- "$1" "$CALL_LOG" || {
		printf 'call log:\n' >&2
		cat "$CALL_LOG" >&2
		fail "expected call log NOT to contain: $1"
	}
}

line_of() {
	grep -Fn -- "$1" "$CALL_LOG" | head -1 | cut -d: -f1
}

# --- Converge before Pi, with the declared tools ahead of the image's -----------

reset_stubs
run_entrypoint pi --version || fail "start with a converged toolchain failed"
# The declaration applies everywhere, so it converges from home; the
# repository's own pins converge from its directory, after it.
assert_call "mise install --yes cwd=$home"
assert_call "mise install --yes cwd=$workdir"
assert_call "data=$data"
# Cache and state sit in the volume even when the wrapper does not set them,
# so the image run directly still keeps its mise state where it survives.
assert_call "cache=$data/cache state=$data/state"
# The sandbox's OTP provenance travels with the image, not the host: the
# precompiled target whose glibc the image satisfies, and the refusal of the
# source fallback that would re-download OTP on every start.
assert_call "precompiled=ubuntu-22.04 compile=false"
assert_call "trusted=$workdir"
assert_call "pi --version"

mise_line="$(line_of "mise install --yes cwd=$workdir")"
pi_line="$(line_of "pi --version")"
[[ -n "$mise_line" && -n "$pi_line" && "$mise_line" -lt "$pi_line" ]] ||
	fail "expected convergence to precede Pi"

# The declared shims come first on PATH, ahead of the image's own binaries.
path_line="$(grep '^pi-path ' "$CALL_LOG" | tail -1)"
IFS=: read -ra path_entries <<<"${path_line#pi-path }"
[[ "${path_entries[0]}" == "$data/shims" ]] ||
	fail "declared shims must lead PATH, got: ${path_entries[0]}"
shims_index=-1
image_index=-1
for i in "${!path_entries[@]}"; do
	[[ "${path_entries[$i]}" == "$data/shims" ]] && shims_index=$i
	[[ "${path_entries[$i]}" == "$IMAGE_BIN" ]] && image_index=$i
done
[[ "$image_index" -gt "$shims_index" && "$shims_index" -ge 0 ]] ||
	fail "declared shims must precede the image's binaries: $path_line"

# --- The locale the sandbox runs under -----------------------------------------
# The wrapper forwards the host's locale as host identity, and the image ships
# en_US.UTF-8 plus glibc's built-in C.UTF-8. A locale glibc cannot resolve falls
# back to the POSIX charmap, which is what started the Erlang VM with latin1
# native name encoding.
# shellcheck disable=SC2016 # expanded by the command that runs inside the sandbox
READ_LOCALES='printf "locale %s|%s|%s\n" "${LANG-}" "${LC_ALL-}" "${LC_CTYPE-}"'

reset_stubs
locale_out="$(run_entrypoint "$bash_bin" -c "$READ_LOCALES")" ||
	fail "run under the host's locale failed"
[[ "$locale_out" == "locale en_US.UTF-8||en_US.UTF-8" ]] ||
	fail "a locale the image ships must be honoured as forwarded, got: $locale_out"

# A locale the image does not ship becomes C.UTF-8 before convergence, so the
# elixir install mise runs converges under UTF-8 too.
reset_stubs
FAKE_LOCALE_LANG=pt_BR.UTF-8
FAKE_LOCALE_LC_CTYPE=pt_BR.UTF-8
locale_out="$(run_entrypoint "$bash_bin" -c "$READ_LOCALES")" ||
	fail "run under a locale the image does not ship failed"
[[ "$locale_out" == "locale C.UTF-8||C.UTF-8" ]] ||
	fail "an unshipped locale must become C.UTF-8, got: $locale_out"
assert_call "lang=C.UTF-8"

# A single-byte locale is replaced even though the image ships it: the sandbox
# is UTF-8, and POSIX is what the latin1 fallback looked like.
reset_stubs
FAKE_LOCALE_LANG=C
FAKE_LOCALE_LC_CTYPE=POSIX
locale_out="$(run_entrypoint "$bash_bin" -c "$READ_LOCALES")" ||
	fail "run under a single-byte locale failed"
[[ "$locale_out" == "locale C.UTF-8||C.UTF-8" ]] ||
	fail "a single-byte locale must become C.UTF-8, got: $locale_out"

# Each of the three is resolved on its own, and an unset one stays unset rather
# than being invented. (bash itself announces an unavailable LC_ALL on startup,
# before the entrypoint can replace it; the assertion is about the environment
# the command ends up with.)
reset_stubs
FAKE_LOCALE_LC_ALL=de_DE.UTF-8
FAKE_LOCALE_LC_CTYPE=""
locale_out="$(run_entrypoint "$bash_bin" -c "$READ_LOCALES")" ||
	fail "run with an unshipped LC_ALL failed"
[[ "$locale_out" == "locale en_US.UTF-8|C.UTF-8|" ]] ||
	fail "LC_ALL must be resolved on its own, got: $locale_out"

# A host that forwards no locale at all keeps the image's own default, which is
# glibc's built-in C.UTF-8 rather than the POSIX charmap.
reset_stubs
FAKE_LOCALE_LANG=""
FAKE_LOCALE_LC_CTYPE=""
locale_out="$(run_entrypoint "$bash_bin" -c "$READ_LOCALES")" ||
	fail "run without a forwarded locale failed"
[[ "$locale_out" == "locale ||" ]] ||
	fail "the entrypoint must not invent a locale, got: $locale_out"

# --- A steady start installs nothing and prints nothing ------------------------
# When every declared tool is installed the probe passes, so the install step
# is skipped and the start is silent; progress is only shown when work is due.
reset_stubs
FAKE_MISE_MISSING=0
steady_out="$(run_entrypoint pi --version 2>&1)" || fail "steady start failed"
[[ -z "$steady_out" || "$steady_out" == "pi --version" ]] ||
	fail "steady start printed convergence output: $steady_out"
assert_no_call "mise-begin"
assert_call "pi --version"

# --- Pins from the repository are trusted and converged from its directory -----
# The trusted list starts with the working directory, so the repository's own
# .mise.toml is honoured; an inherited value is kept after it.
reset_stubs
FAKE_INHERITED_TRUST=/elsewhere
run_entrypoint pi -c >/dev/null || fail "start with an inherited trust list failed"
assert_call "trusted=$workdir:/elsewhere"

# --- The declaration converges even when a repository pin fails -----------------
# A repository that pins a tool the declaration also names must not stop the
# declared environment from converging, and the failure is still reported.
reset_stubs
FAKE_MISE_FAIL_CWD="$workdir"
fail_status="$(status_of run_entrypoint --prepare 2>"$tmpdir/pin.err")"
[[ "$fail_status" == "1" ]] || fail "a failing repository pin must exit 1, got $fail_status"
assert_call "mise install --yes cwd=$home"
assert_call "mise install --yes cwd=$workdir"

# --- Prepare converges strictly and never starts Pi ---------------------------

reset_stubs
run_entrypoint --prepare || fail "prepare with a converged toolchain failed"
assert_call "mise install --yes"
assert_no_call "pi "

reset_stubs
FAKE_MISE_STATUS=3
prepare_status="$(status_of run_entrypoint --prepare 2>"$tmpdir/prepare.err")"
[[ "$prepare_status" == "1" ]] || fail "prepare must exit 1 on convergence failure, got $prepare_status"
grep -Fq "mise install --yes" "$tmpdir/prepare.err" ||
	fail "prepare failure must name the failed step: $(cat "$tmpdir/prepare.err")"
assert_no_call "pi "

# --- Fail-open: a failed convergence warns and Pi still starts ----------------

reset_stubs
FAKE_MISE_STATUS=3
FAKE_PI_STATUS=5
open_status="$(status_of run_entrypoint pi -c 2>"$tmpdir/open.err")"
[[ "$open_status" == "5" ]] || fail "fail-open start must exit with Pi's status, got $open_status"
grep -Fq "warning" "$tmpdir/open.err" || fail "fail-open start must warn: $(cat "$tmpdir/open.err")"
grep -Fq "mise install --yes" "$tmpdir/open.err" ||
	fail "fail-open warning must name the failed step: $(cat "$tmpdir/open.err")"
assert_call "pi -c"

# --- Engine requirement: Pi refuses to start on an unsatisfied Node -----------

reset_stubs
npm_root="$npm_unsatisfied"
engine_status="$(status_of run_entrypoint pi --version 2>"$tmpdir/engine.err")"
[[ "$engine_status" == "1" ]] || fail "unsatisfied engine must exit 1, got $engine_status"
grep -Fq ">=99.0.0" "$tmpdir/engine.err" ||
	fail "engine failure must name the requirement: $(cat "$tmpdir/engine.err")"
assert_no_call "pi --version"

# The check guards Pi only; a shell in the sandbox still opens so the failure
# can be diagnosed from inside.
reset_stubs
npm_root="$npm_unsatisfied"
shell_out="$(run_entrypoint "$bash_bin" -c 'printf shell-ran')" ||
	fail "a shell must not be blocked by the engine check"
[[ "$shell_out" == "shell-ran" ]] || fail "shell did not run its command: $shell_out"

# Without a readable Pi package the requirement cannot be checked: warn, start.
reset_stubs
npm_root="$npm_no_pi"
unverified_status="$(status_of run_entrypoint pi -c 2>"$tmpdir/unverified.err")"
[[ "$unverified_status" == "0" ]] || fail "unverifiable engine must still start Pi, got $unverified_status"
grep -Fq "warning" "$tmpdir/unverified.err" || fail "unverifiable engine must warn"
assert_call "pi -c"

# --- Containers sharing the volume converge one at a time ---------------------

reset_stubs
FAKE_MISE_SLEEP=1
run_entrypoint --prepare >"$tmpdir/first.out" 2>&1 &
first_pid=$!
run_entrypoint --prepare >"$tmpdir/second.out" 2>&1 &
second_pid=$!
wait "$first_pid" || fail "first concurrent prepare failed"
wait "$second_pid" || fail "second concurrent prepare failed"
# Each container converges twice (declaration, then pins), so the lock must
# keep every begin/end pair whole, one container at a time.
sequence="$(grep -E '^mise-(begin|end)$' "$CALL_LOG" | paste -sd' ' -)"
expected="$(printf 'mise-begin mise-end %.0s' 1 2 3 4 | sed 's/ $//')"
[[ "$sequence" == "$expected" ]] || fail "concurrent convergence overlapped: $sequence"

# --- The sandbox package tree --------------------------------------------------
# Pi's npm packages carry one native binding per platform, so the sandbox installs
# its own tree from the host's package.json and package-lock.json (ADR 0009). The
# wrapper mounts those two files at SAFE_PI_HOST_NPM_DIR's default; the tests
# point it at a fixture. `npm` is a stub, so nothing is downloaded.
make_host_npm() { # writes a host declaration into $host_npm
	mkdir -p "$host_npm"
	printf '{"name":"pi-extensions","dependencies":{"a":"1"}}\n' >"$host_npm/package.json"
	printf '{"lockfileVersion":3,"packages":{}}\n' >"$host_npm/package-lock.json"
}

ci_count() { grep -c '^npm-ci-begin' "$CALL_LOG" || true; }

# A first start installs, in the tree, from a copy of the host's declaration,
# with the image's own PATH and the flag Pi's installs use, and starts Pi after.
reset_stubs
make_host_npm
FAKE_MISE_MISSING=0
run_entrypoint pi --version >"$tmpdir/first-npm.out" 2>"$tmpdir/first-npm.err" ||
	fail "first start with a host lock failed"
[[ "$(ci_count)" == "1" ]] || fail "a first start must install once, got $(ci_count)"
assert_call "npm ci --legacy-peer-deps"
assert_call "npm-ci-begin cwd=$sandbox_npm path=$IMAGE_BIN:"
assert_no_call "path=$data/shims"
cmp -s "$host_npm/package-lock.json" "$sandbox_npm/package-lock.json" ||
	fail "the install must run from the host's lock"
cmp -s "$host_npm/package.json" "$sandbox_npm/package.json" ||
	fail "the install must run from the host's package.json"
[[ -s "$sandbox_npm/.safe-pi-stamp" ]] || fail "a successful install must write the stamp"
grep -Fq "npm-ci-output" "$tmpdir/first-npm.err" ||
	fail "the install's progress must be shown: $(cat "$tmpdir/first-npm.err")"
[[ "$(<"$tmpdir/first-npm.out")" == "" ]] || fail "the install must not write to stdout"
assert_call "pi --version"
ci_line="$(line_of "npm-ci-begin")"
pi_line="$(line_of "pi --version")"
[[ "$ci_line" -lt "$pi_line" ]] || fail "the package tree must converge before Pi starts"

# An unchanged key installs nothing and prints nothing: a steady start.
: >"$CALL_LOG"
steady_out="$(run_entrypoint pi --version 2>&1)" || fail "steady start with a host lock failed"
[[ "$steady_out" == "" || "$steady_out" == "pi --version" ]] ||
	fail "a steady start must print nothing, got: $steady_out"
[[ "$(ci_count)" == "0" ]] || fail "an unchanged key must install nothing"

# The debug shell converges the tree too: any start does.
reset_stubs
make_host_npm
run_entrypoint "$bash_bin" -c true 2>/dev/null || fail "shell start with a host lock failed"
[[ "$(ci_count)" == "1" ]] || fail "a shell start must converge the package tree"

# A changed lock reinstalls, and so does a changed Node ABI.
reset_stubs
make_host_npm
run_entrypoint pi --version >/dev/null 2>&1 || fail "start before the lock changed failed"
printf '{"lockfileVersion":3,"packages":{"x":{}}}\n' >"$host_npm/package-lock.json"
run_entrypoint pi --version >/dev/null 2>&1 || fail "start after the lock changed failed"
[[ "$(ci_count)" == "2" ]] || fail "a changed lock must reinstall, got $(ci_count) installs"
cmp -s "$host_npm/package-lock.json" "$sandbox_npm/package-lock.json" ||
	fail "the reinstall must use the changed lock"
FAKE_NODE_ABI=141
run_entrypoint pi --version >/dev/null 2>&1 || fail "start after the Node ABI changed failed"
[[ "$(ci_count)" == "3" ]] || fail "a changed Node ABI must reinstall, got $(ci_count) installs"
run_entrypoint pi --version >/dev/null 2>&1 || fail "start after the reinstall failed"
[[ "$(ci_count)" == "3" ]] || fail "a converged tree must not reinstall again"

# A changed package.json reinstalls as well: it is part of the key.
printf '{"name":"pi-extensions","dependencies":{"b":"2"}}\n' >"$host_npm/package.json"
run_entrypoint pi --version >/dev/null 2>&1 || fail "start after package.json changed failed"
[[ "$(ci_count)" == "4" ]] || fail "a changed package.json must reinstall"

# A failed install writes no stamp, warns naming the step, and Pi still starts;
# the next start tries again.
reset_stubs
make_host_npm
FAKE_NPM_CI_STATUS=7
FAKE_PI_STATUS=5
npm_fail_status="$(status_of run_entrypoint pi -c 2>"$tmpdir/npm-fail.err")"
[[ "$npm_fail_status" == "5" ]] ||
	fail "a failed install must still start Pi and exit with its status, got $npm_fail_status"
[[ ! -e "$sandbox_npm/.safe-pi-stamp" ]] || fail "a failed install must not write the stamp"
grep -Fq "warning" "$tmpdir/npm-fail.err" || fail "a failed install must warn: $(cat "$tmpdir/npm-fail.err")"
grep -Fq "npm ci --legacy-peer-deps" "$tmpdir/npm-fail.err" ||
	fail "the warning must name the failed step: $(cat "$tmpdir/npm-fail.err")"
assert_call "pi -c"
FAKE_NPM_CI_STATUS=0
FAKE_PI_STATUS=0
run_entrypoint pi -c >/dev/null 2>&1 || fail "the start after a failed install failed"
[[ "$(ci_count)" == "2" ]] || fail "a failed install must be retried on the next start"
[[ -s "$sandbox_npm/.safe-pi-stamp" ]] || fail "the retry must write the stamp"

# A failed reinstall leaves no stamp from the previous key either.
printf '{"lockfileVersion":3,"packages":{"y":{}}}\n' >"$host_npm/package-lock.json"
FAKE_NPM_CI_STATUS=7
run_entrypoint pi -c >/dev/null 2>&1 || fail "a failed reinstall must still start Pi"
[[ ! -e "$sandbox_npm/.safe-pi-stamp" ]] ||
	fail "a failed reinstall must not leave the previous key's stamp"

# Under --prepare the same failure is an error naming the step, and Pi does not
# start; --prepare converges the package tree as well as the toolchain.
reset_stubs
make_host_npm
FAKE_NPM_CI_STATUS=7
prepare_npm_status="$(status_of run_entrypoint --prepare 2>"$tmpdir/prepare-npm.err")"
[[ "$prepare_npm_status" == "1" ]] || fail "prepare must exit 1 on a failed install, got $prepare_npm_status"
grep -Fq "npm ci --legacy-peer-deps" "$tmpdir/prepare-npm.err" ||
	fail "prepare failure must name the failed step: $(cat "$tmpdir/prepare-npm.err")"
assert_no_call "pi "
reset_stubs
make_host_npm
run_entrypoint --prepare >/dev/null 2>&1 || fail "prepare with a host lock failed"
[[ "$(ci_count)" == "1" && -s "$sandbox_npm/.safe-pi-stamp" ]] ||
	fail "prepare must converge the package tree"

# The two convergences are independent: a failed toolchain does not skip the
# package tree, and prepare reports each.
reset_stubs
make_host_npm
FAKE_MISE_STATUS=3
both_status="$(status_of run_entrypoint --prepare 2>"$tmpdir/both.err")"
[[ "$both_status" == "1" ]] || fail "prepare must exit 1 when the toolchain fails, got $both_status"
[[ "$(ci_count)" == "1" ]] || fail "a failed toolchain must not skip the package tree"

# No host lock: nothing is declared, so convergence skips, silently. A lock
# without a package.json cannot be installed from and skips the same way.
reset_stubs
FAKE_MISE_MISSING=0
silent_out="$(run_entrypoint pi --version 2>&1)" || fail "start without a host lock failed"
[[ "$silent_out" == "" || "$silent_out" == "pi --version" ]] ||
	fail "no host lock must skip silently, got: $silent_out"
[[ "$(ci_count)" == "0" ]] || fail "no host lock must install nothing"
[[ ! -e "$sandbox_npm/.safe-pi-stamp" ]] || fail "no host lock must write no stamp"
mkdir -p "$host_npm"
printf '{}\n' >"$host_npm/package-lock.json"
run_entrypoint pi --version >/dev/null 2>&1 || fail "start with a lock but no package.json failed"
[[ "$(ci_count)" == "0" ]] || fail "a lock without a package.json must install nothing"

# Starts sharing the tree install one at a time: the second waits, then finds
# the tree converged.
reset_stubs
make_host_npm
FAKE_NPM_CI_SLEEP=1
run_entrypoint "$bash_bin" -c true >"$tmpdir/npm-first.out" 2>&1 &
npm_first_pid=$!
run_entrypoint "$bash_bin" -c true >"$tmpdir/npm-second.out" 2>&1 &
npm_second_pid=$!
wait "$npm_first_pid" || fail "first concurrent start failed"
wait "$npm_second_pid" || fail "second concurrent start failed"
[[ "$(ci_count)" == "1" ]] || fail "concurrent starts must install once, got $(ci_count)"
[[ "$(grep -c '^npm-ci-end' "$CALL_LOG")" == "1" ]] || fail "the install must finish once"

# --- The sandbox reporter ships in the image -----------------------------------
# The wrapper loads it explicitly with `-e`, so the image must carry it and its
# directory must be traversable; the reporter's behavior is covered by the Pi
# suite (pi/tests/pi-agent/herdr-reporter.test.ts).
[[ -f "$repo_root/safe-pi/herdr-reporter.ts" ]] ||
	fail "the sandbox reporter must live in the image build context"
grep -Fq "herdr-reporter.ts" "$repo_root/safe-pi/Dockerfile" ||
	fail "the image must copy the sandbox reporter"
# The reporter directory is created explicitly so it is traversable whatever
# mode the COPY would give an implicitly-created destination directory.
grep -Fq "install -d -m 0755 /usr/local/share/safe-pi" "$repo_root/safe-pi/Dockerfile" ||
	fail "the reporter directory must be created traversable before the COPY"

# --- The image builds without BuildKit -----------------------------------------
# A host whose Docker CLI has no buildx plugin (Homebrew docker + Colima) falls
# back to the legacy builder, which rejects BuildKit-only instruction flags. The
# modes the entrypoint and reporter need are set with an explicit chmod instead.
if grep -En '^[[:space:]]*(COPY|ADD|RUN)[[:space:]]+--(chmod|chown|link|mount|network|security|parents|exclude|checksum|keep-git-dir)' \
	"$repo_root/safe-pi/Dockerfile"; then
	fail "the image must build under the legacy builder (no BuildKit-only flags)"
fi
grep -Fq "chmod 0755 /usr/local/bin/safe-pi-entrypoint" "$repo_root/safe-pi/Dockerfile" ||
	fail "the image must make the entrypoint executable explicitly"
grep -Fq "chmod 0644 /usr/local/share/safe-pi/herdr-reporter.ts" "$repo_root/safe-pi/Dockerfile" ||
	fail "the image must make the reporter world-readable explicitly"

# --- The image ships the locale the wrapper forwards ---------------------------
# The sandbox runs under the host's locale, and only the image can ship it: the
# `locales` source data, the generated locale, and the UTF-8 default a direct
# image run starts under.
grep -Fq "localedef -i en_US -f UTF-8 en_US.UTF-8" "$repo_root/safe-pi/Dockerfile" ||
	fail "the image must generate the locale the wrapper forwards"
grep -Fq "locale -a | grep -qix 'C\\.utf8'" "$repo_root/safe-pi/Dockerfile" ||
	fail "the image must ship the C.UTF-8 the entrypoint falls back to"
grep -Fq "ENV LANG=C.UTF-8" "$repo_root/safe-pi/Dockerfile" ||
	fail "a direct image run must default to a UTF-8 locale"

printf 'safe-pi entrypoint tests passed\n'
