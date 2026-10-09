#!/usr/bin/env bash
# tier: slow
# Tests for the sandbox entrypoint at its external boundaries.
#
# The entrypoint converges the declared environment with `mise`, puts the
# declared shims ahead of the image's binaries, checks Pi's Node engine
# requirement, and then runs the command. This harness runs the real script
# with stubs for `mise`, `pi`, and `npm` on a controlled PATH and asserts on
# the calls, environment, ordering, and exit codes it produces. No Docker
# daemon is required.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="$repo_root/safe-pi/entrypoint.sh"
bash_bin="$(command -v bash)"
tmpdir="$(mktemp -d)"
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
printf 'mise %s cwd=%s trusted=%s data=%s cache=%s state=%s\n' "$*" "$PWD" \
	"${MISE_TRUSTED_CONFIG_PATHS-}" "${MISE_DATA_DIR-}" \
	"${MISE_CACHE_DIR-}" "${MISE_STATE_DIR-}" >>"$log"
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
exit 99
NPM
chmod +x "$IMAGE_BIN/npm"

cat >"$IMAGE_BIN/pi" <<'PI'
#!/usr/bin/env bash
set -euo pipefail
printf 'pi %s\n' "$*" >>"${SAFE_PI_TEST_LOG:?}"
printf 'pi-path %s\n' "$PATH" >>"$SAFE_PI_TEST_LOG"
exit "${SAFE_PI_FAKE_PI_STATUS:-0}"
PI
chmod +x "$IMAGE_BIN/pi"

ln -s "$(command -v node)" "$IMAGE_BIN/node"

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
workdir="$tmpdir/repo"
mkdir -p "$home" "$workdir"

reset_stubs() {
	: >"$CALL_LOG"
	rm -rf "$data"
	mkdir -p "$data"
	npm_root="$npm_ok"
	FAKE_MISE_STATUS=0
	FAKE_MISE_SLEEP=0
	FAKE_PI_STATUS=0
	FAKE_INHERITED_TRUST=""
	FAKE_MISE_FAIL_CWD=""
	FAKE_MISE_MISSING=1
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
			MISE_DATA_DIR="$data" \
			MISE_TRUSTED_CONFIG_PATHS="$FAKE_INHERITED_TRUST" \
			SAFE_PI_TEST_LOG="$CALL_LOG" \
			SAFE_PI_TEST_NPM_ROOT="$npm_root" \
			SAFE_PI_FAKE_MISE_STATUS="$FAKE_MISE_STATUS" \
			SAFE_PI_FAKE_MISE_SLEEP="$FAKE_MISE_SLEEP" \
			SAFE_PI_FAKE_MISE_FAIL_CWD="$FAKE_MISE_FAIL_CWD" \
			SAFE_PI_FAKE_MISE_MISSING="$FAKE_MISE_MISSING" \
			SAFE_PI_FAKE_PI_STATUS="$FAKE_PI_STATUS" \
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
sequence="$(grep -E '^mise-(begin|end)$' "$CALL_LOG" | paste -sd' ')"
expected="$(printf 'mise-begin mise-end %.0s' 1 2 3 4 | sed 's/ $//')"
[[ "$sequence" == "$expected" ]] || fail "concurrent convergence overlapped: $sequence"

# --- The sandbox reporter ships in the image -----------------------------------
# The wrapper loads it explicitly with `-e`, so the image must carry it and its
# directory must be traversable; the reporter's behavior is covered by the Pi
# suite (pi/tests/pi-agent/herdr-reporter.test.ts).
[[ -f "$repo_root/safe-pi/herdr-reporter.ts" ]] ||
	fail "the sandbox reporter must live in the image build context"
grep -Fq "herdr-reporter.ts" "$repo_root/safe-pi/Dockerfile" ||
	fail "the image must copy the sandbox reporter"
# BuildKit applies `--chmod` to an implicitly-created destination directory, so
# a missing explicit `install -d` leaves the reporter directory non-traversable.
grep -Fq "install -d -m 0755 /usr/local/share/safe-pi" "$repo_root/safe-pi/Dockerfile" ||
	fail "the reporter directory must be created traversable before the COPY"

printf 'safe-pi entrypoint tests passed\n'
