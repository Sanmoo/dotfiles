#!/usr/bin/env bash
# Tests for the safe-pi wrapper at the docker process boundary.
#
# The wrapper's only external collaborator is the `docker` command (plus `npm`
# for the refresh lookup). This harness puts stubs for both on PATH and runs
# the real script, asserting on the arguments, ordering, and exit codes it
# produces. No Docker daemon is required.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$repo_root/pi/.local/bin/safe-pi"
bash_bin="$(command -v bash)"
tmpdir="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmpdir"' EXIT

BIN="$tmpdir/bin"
mkdir -p "$BIN"

DOCKER_LOG="$tmpdir/docker.log"
NPM_LOG="$tmpdir/npm.log"
PI_LOG="$tmpdir/pi.log"
: >"$DOCKER_LOG"
: >"$NPM_LOG"
: >"$PI_LOG"

uid="$(id -u)"
current_tag="safe-pi:current-u$uid"
reporter="-e /usr/local/share/safe-pi/herdr-reporter.ts"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

# Stub the docker boundary. It records every invocation, answers the two
# probes the wrapper makes (daemon reachability, image existence), and lets
# the test pick which images already exist.
cat >"$BIN/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker %s\n' "$*" >>"${SAFE_PI_DOCKER_LOG:?}"
cmd="${1:-}"
sub="${2:-}"
case "$cmd" in
	info)
		if [[ "${SAFE_PI_FAKE_DOCKER_UP:-1}" != "1" ]]; then
			printf 'Cannot connect to the Docker daemon\n' >&2
			exit 1
		fi
		exit 0
		;;
	run)
		exit "${SAFE_PI_FAKE_RUN_STATUS:-0}"
		;;
	tag | build)
		exit 0
		;;
	image)
		[[ "$sub" == "inspect" ]] || {
			printf 'stub docker: unexpected image subcommand: %s\n' "$*" >&2
			exit 99
		}
		tag="${*: -1}"
		if grep -Fxq -- "$tag" <<<"${SAFE_PI_FAKE_IMAGES:-}"; then
			if [[ "$*" == *"safe-pi.entrypoint"* ]]; then
				printf '%s\n' "${SAFE_PI_FAKE_ENTRYPOINT-}"
			elif [[ " $* " == *" --format "* ]]; then
				printf '%s\n' "${SAFE_PI_FAKE_PI_VERSION:-1.1.0}"
			fi
			exit 0
		fi
		exit 1
		;;
	*)
		printf 'stub docker: unexpected command: %s\n' "$*" >&2
		exit 99
		;;
esac
DOCKER
chmod +x "$BIN/docker"

# Stub the npm registry lookup used by the refresh flag.
cat >"$BIN/npm" <<'NPM'
#!/usr/bin/env bash
set -euo pipefail
printf 'npm %s\n' "$*" >>"${SAFE_PI_NPM_LOG:?}"
printf '%s\n' "${SAFE_PI_FAKE_LATEST_PI:-9.9.9}"
NPM
chmod +x "$BIN/npm"

# A stub pi for the re-entry guard, which runs pi directly.
cat >"$BIN/pi" <<'PI'
#!/usr/bin/env bash
set -euo pipefail
printf 'pi %s\n' "$*" >>"${SAFE_PI_PI_LOG:?}"
if [[ "${1-}" == "--version" ]]; then
	printf '%s\n' "${SAFE_PI_FAKE_HOST_PI_VERSION:-}"
	exit 0
fi
exit "${SAFE_PI_FAKE_PI_STATUS:-0}"
PI
chmod +x "$BIN/pi"

reset_stubs() {
	: >"$DOCKER_LOG"
	: >"$NPM_LOG"
	: >"$PI_LOG"
	FAKE_IMAGES=""
	FAKE_PI_VERSION="1.1.0"
	FAKE_LATEST_PI="9.9.9"
	FAKE_DOCKER_UP=1
	FAKE_RUN_STATUS=0
	FAKE_HOST_PI_VERSION=""
	FAKE_ENTRYPOINT="4"
}

# run_safe_pi [--cwd DIR] [script args...]
# Runs the real script with the stub boundary on PATH. Callers set the
# SAFE_PI_FAKE_* knobs to steer the stubs.
run_safe_pi() {
	local cwd="$PWD"
	while [[ "${1-}" == "--cwd" ]]; do
		cwd="$2"
		shift 2
	done
	(
		cd "$cwd"
		export HOME="${SAFE_PI_TEST_HOME:-$HOME}"
		case "${SAFE_PI_TEST_SSH-}" in
		set) export SSH_AUTH_SOCK="${SAFE_PI_TEST_SSH_SOCK-}" ;;
		unset) unset SSH_AUTH_SOCK ;;
		esac
		case "${SAFE_PI_TEST_HERDR-}" in
		set) export HERDR_ENV=1 HERDR_SOCKET_PATH=/tmp/safe-pi-test-herdr.sock HERDR_PANE_ID=wtest:p1 ;;
		unset) unset HERDR_ENV HERDR_SOCKET_PATH HERDR_PANE_ID ;;
		esac
		if [[ -n "${SAFE_PI_TEST_PATH-}" ]]; then
			path="$SAFE_PI_TEST_PATH"
		else
			path="${SAFE_PI_TEST_BIN:-$BIN}:$PATH"
		fi
		SAFE_PI_DOCKER_LOG="$DOCKER_LOG" \
			SAFE_PI_NPM_LOG="$NPM_LOG" \
			SAFE_PI_PI_LOG="$PI_LOG" \
			PATH="$path" \
			SAFE_PI_FAKE_IMAGES="${FAKE_IMAGES-}" \
			SAFE_PI_FAKE_PI_VERSION="${FAKE_PI_VERSION-1.1.0}" \
			SAFE_PI_FAKE_LATEST_PI="${FAKE_LATEST_PI-9.9.9}" \
			SAFE_PI_FAKE_DOCKER_UP="${FAKE_DOCKER_UP-1}" \
			SAFE_PI_FAKE_RUN_STATUS="${FAKE_RUN_STATUS-0}" \
			SAFE_PI_FAKE_HOST_PI_VERSION="${FAKE_HOST_PI_VERSION-}" \
			SAFE_PI_FAKE_ENTRYPOINT="${FAKE_ENTRYPOINT-1}" \
			"$bash_bin" "${SAFE_PI_TEST_SCRIPT:-$SCRIPT}" "$@"
	)
}

status_of() {
	local status
	set +e
	"$@"
	status=$?
	set -e
	printf '%s' "$status"
}

assert_log() {
	grep -Fq -- "$1" "$DOCKER_LOG" || {
		printf 'docker log:\n' >&2
		cat "$DOCKER_LOG" >&2
		fail "expected docker log to contain: $1"
	}
}

assert_no_log() {
	! grep -Fq -- "$1" "$DOCKER_LOG" || {
		printf 'docker log:\n' >&2
		cat "$DOCKER_LOG" >&2
		fail "expected docker log NOT to contain: $1"
	}
}

assert_npm() {
	grep -Fq -- "$1" "$NPM_LOG" || {
		printf 'npm log:\n' >&2
		cat "$NPM_LOG" >&2
		fail "expected npm log to contain: $1"
	}
}

log_line_of() {
	grep -Fn -- "$1" "$DOCKER_LOG" | head -1 | cut -d: -f1
}

# --- First slice: build when absent, run, and forward arguments ---------------

FAKE_IMAGES=""
run_safe_pi -- --model test/model "a b" || fail "normal run failed"

assert_log "docker build --tag $current_tag"
assert_log "docker run --rm"
assert_log "--workdir $PWD"
assert_log "--volume $PWD:$PWD"
assert_log " pi $reporter --model test/model a b"

build_line="$(log_line_of "docker build --tag $current_tag")"
run_line="$(log_line_of "docker run --rm")"
[[ -n "$build_line" && -n "$run_line" && "$build_line" -lt "$run_line" ]] ||
	fail "expected the build to precede the run"

# --- Skip the build when the current tag already exists ------------------------

reset_stubs
FAKE_IMAGES="$current_tag"
run_safe_pi -c || fail "cached run failed"
assert_no_log "docker build"
assert_log " pi $reporter -c"

# --- The working directory is the invoking directory --------------------------

reset_stubs
FAKE_IMAGES="$current_tag"
invoked="$tmpdir/invoked"
mkdir -p "$invoked"
run_safe_pi --cwd "$invoked" -c || fail "run from another directory failed"
assert_log "--workdir $invoked"
assert_log "--volume $invoked:$invoked"
assert_log "--env SAFE_PI_SANDBOX=1"

# --- Forced rebuild rebuilds the current tag -----------------------------------

reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_PI_VERSION="2.2.2"
run_safe_pi --rebuild --model test/model || fail "rebuild run failed"
assert_log "docker build --tag $current_tag"
assert_log "--build-arg PI_VERSION=2.2.2"
assert_log "docker tag $current_tag safe-pi:pi-2.2.2-u$uid"
assert_log " pi $reporter --model test/model"

# --- Refresh resolves the latest release and re-points the current tag ----------

reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_LATEST_PI="3.3.3"
run_safe_pi --update --shell || fail "update run failed"
assert_log "docker build --tag safe-pi:pi-3.3.3-u$uid"
assert_log "--build-arg PI_VERSION=3.3.3"
assert_log "docker tag safe-pi:pi-3.3.3-u$uid $current_tag"
assert_log " bash"
assert_npm "npm view @earendil-works/pi-coding-agent version"

# A version tag that already exists is reused without a build.
reset_stubs
FAKE_IMAGES="$current_tag
safe-pi:pi-3.3.3-u$uid"
FAKE_LATEST_PI="3.3.3"
run_safe_pi --update || fail "update reuse run failed"
assert_no_log "docker build"
assert_log "docker tag safe-pi:pi-3.3.3-u$uid $current_tag"
assert_log "docker run --rm"

# An image built before the entrypoint existed is rebuilt, rather than run
# without convergence; a stale version tag is not reused by --update either.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_ENTRYPOINT=""
run_safe_pi -c 2>"$tmpdir/stale.err" || fail "stale image run failed"
assert_log "docker build --tag $current_tag"
assert_log "--build-arg PI_VERSION=1.1.0"
assert_log "docker run --rm"
grep -Fq "entrypoint" "$tmpdir/stale.err" || fail "stale image rebuild should say why"

# An image from a previous entrypoint version is stale too: it predates the
# sandbox locale, so it would resolve the forwarded locale no better than the
# POSIX fallback that made every `elixir` invocation warn.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_ENTRYPOINT="3"
run_safe_pi -c 2>"$tmpdir/stale-v3.err" || fail "v3-entrypoint image run failed"
assert_log "docker build --tag $current_tag"
assert_log "docker run --rm"
grep -Fq "entrypoint" "$tmpdir/stale-v3.err" || fail "v3-entrypoint rebuild should say why"

reset_stubs
FAKE_IMAGES="$current_tag
safe-pi:pi-3.3.3-u$uid"
FAKE_ENTRYPOINT=""
FAKE_LATEST_PI="3.3.3"
run_safe_pi --update || fail "stale version tag update failed"
assert_log "docker build --tag safe-pi:pi-3.3.3-u$uid"

# A current image with the entrypoint is not rebuilt.
reset_stubs
FAKE_IMAGES="$current_tag"
run_safe_pi -c || fail "current image run failed"
assert_no_log "docker build"

# The version the wrapper accepts is the label the Dockerfile writes: if the two
# drift, an existing image is either never rebuilt or rebuilt on every run.
dockerfile_label="$(grep -o 'safe-pi.entrypoint="[0-9]*"' "$repo_root/safe-pi/Dockerfile" | grep -o '[0-9]*')"
[[ -n "$dockerfile_label" ]] || fail "the Dockerfile must label its entrypoint version"
grep -Fq "== \"$dockerfile_label\"" "$SCRIPT" ||
	fail "the wrapper must require the image's entrypoint version $dockerfile_label"

# A normal run performs no version lookup.
reset_stubs
FAKE_IMAGES="$current_tag"
run_safe_pi -c || fail "normal run failed"
[[ ! -s "$NPM_LOG" ]] || fail "normal run must not query npm"

# --- Dry run prints the invocation and never touches Docker --------------------

reset_stubs
FAKE_IMAGES="$current_tag"
dry_output="$(run_safe_pi --dry-run -c)" || fail "dry run failed"
[[ ! -s "$DOCKER_LOG" ]] || fail "dry run must not invoke docker"
[[ ! -s "$NPM_LOG" ]] || fail "dry run must not invoke npm"
case "$dry_output" in
*"docker run --rm"*) ;;
*) fail "dry run output missing the docker run invocation: $dry_output" ;;
esac
case "$dry_output" in
*"$current_tag"*) ;;
*) fail "dry run output missing the image tag: $dry_output" ;;
esac

# --- help subcommand, and --help/--version forwarded to Pi ---------------------

reset_stubs
run_safe_pi help >/dev/null || fail "help subcommand failed"
[[ ! -s "$DOCKER_LOG" ]] || fail "help must not invoke docker"

for flag in -h --help --version; do
	reset_stubs
	FAKE_IMAGES="$current_tag"
	run_safe_pi "$flag" || fail "forwarding $flag failed"
	assert_log " pi $reporter $flag"
done

# --- Warn when the image's Pi differs from the host's Pi -----------------------

reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_PI_VERSION="2.2.2"
FAKE_HOST_PI_VERSION="1.1.0"
set +e
drift_stderr="$(run_safe_pi -c 2>&1 >/dev/null)"
drift_status=$?
set -e
[[ "$drift_status" == "0" ]] || fail "version drift must not block Pi, got $drift_status"
case "$drift_stderr" in
*2.2.2*1.1.0*) ;;
*) fail "version drift warning should name both versions: $drift_stderr" ;;
esac

reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_PI_VERSION="1.1.0"
FAKE_HOST_PI_VERSION="1.1.0"
set +e
matching_stderr="$(run_safe_pi -c 2>&1 >/dev/null)"
matching_status=$?
set -e
[[ "$matching_status" == "0" ]] || fail "matching versions should run, got $matching_status"
case "$matching_stderr" in
*"warning"*) fail "no warning expected when versions match: $matching_stderr" ;;
*) ;;
esac

# --- Exit status is Pi's -------------------------------------------------------

reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_RUN_STATUS=7
status="$(status_of run_safe_pi -c)"
[[ "$status" == "7" ]] || fail "expected docker's exit status to pass through, got $status"

# --- Refuse to run as root -----------------------------------------------------

rootbin="$tmpdir/rootbin"
mkdir -p "$rootbin"
cat >"$rootbin/id" <<'ID'
#!/usr/bin/env bash
case "$1" in
-u) printf '0\n' ;;
-g) printf '0\n' ;;
-un) printf 'root\n' ;;
*) exec /usr/bin/id "$@" ;;
esac
ID
chmod +x "$rootbin/id"
reset_stubs
set +e
root_stderr="$(SAFE_PI_TEST_BIN="$rootbin" run_safe_pi -c 2>&1 >/dev/null)"
root_status=$?
set -e
[[ "$root_status" == "2" ]] || fail "root run should exit 2, got $root_status"
case "$root_stderr" in
*root*) ;;
*) fail "root refusal message not actionable: $root_stderr" ;;
esac
assert_no_log "docker"

# --- Refuse without a reachable Docker -----------------------------------------

nobin="$tmpdir/nobin"
mkdir -p "$nobin"
for tool in id readlink dirname mkdir; do
	ln -s "$(command -v "$tool")" "$nobin/$tool"
done
reset_stubs
set +e
missing_stderr="$(SAFE_PI_TEST_PATH="$nobin" run_safe_pi -c 2>&1 >/dev/null)"
missing_status=$?
set -e
[[ "$missing_status" == "2" ]] || fail "missing docker should exit 2, got $missing_status"
case "$missing_stderr" in
*Docker*) ;;
*) fail "missing-docker message not actionable: $missing_stderr" ;;
esac

reset_stubs
set +e
down_stderr="$(FAKE_DOCKER_UP=0 run_safe_pi -c 2>&1 >/dev/null)"
down_status=$?
set -e
[[ "$down_status" == "2" ]] || fail "unreachable docker should exit 2, got $down_status"
case "$down_stderr" in
*"Docker daemon"*) ;;
*) fail "unreachable-docker message not actionable: $down_stderr" ;;
esac

# --- Re-entry guard runs Pi directly -------------------------------------------

reset_stubs
SAFE_PI_SANDBOX=1 run_safe_pi -c --model test/model || fail "re-entry run failed"
[[ ! -s "$DOCKER_LOG" ]] || fail "re-entry must not invoke docker"
grep -Fq -- "pi -c --model test/model" "$PI_LOG" || fail "re-entry did not execute pi with the arguments"

# --- Build context resolution --------------------------------------------------

# Resolution follows the stow symlink into the repository.
reset_stubs
ln -s "$SCRIPT" "$tmpdir/safe-pi-link"
SAFE_PI_TEST_SCRIPT="$tmpdir/safe-pi-link" run_safe_pi -c || fail "symlinked run failed"
assert_log "--file $repo_root/safe-pi/Dockerfile"

# A copied script fails with an actionable message.
reset_stubs
mkdir -p "$tmpdir/copied"
cp "$SCRIPT" "$tmpdir/copied/safe-pi"
set +e
copied_stderr="$(SAFE_PI_TEST_SCRIPT="$tmpdir/copied/safe-pi" run_safe_pi -c 2>&1 >/dev/null)"
copied_status=$?
set -e
[[ "$copied_status" == "2" ]] || fail "copied script should exit 2, got $copied_status"
case "$copied_stderr" in
*SAFE_PI_BUILD_CONTEXT*) ;;
*) fail "copied-script message not actionable: $copied_stderr" ;;
esac
assert_no_log "docker"

# The override is honored, as a directory or a Dockerfile path.
altcontext="$tmpdir/alt-context"
mkdir -p "$altcontext"
cp "$repo_root/safe-pi/Dockerfile" "$altcontext/Dockerfile"
reset_stubs
SAFE_PI_BUILD_CONTEXT="$altcontext" run_safe_pi -c || fail "override directory run failed"
assert_log "--file $altcontext/Dockerfile"

reset_stubs
SAFE_PI_BUILD_CONTEXT="$altcontext/Dockerfile" run_safe_pi -c || fail "override file run failed"
assert_log "--file $altcontext/Dockerfile"

# --- Flags after `--` are forwarded to Pi, script-owned or not -----------------

reset_stubs
FAKE_IMAGES="$current_tag"
run_safe_pi -- --rebuild --shell --dry-run || fail "pass-through run failed"
assert_log " pi $reporter --rebuild --shell --dry-run"
assert_log "docker run --rm"
assert_no_log "docker build"

# --- Container contract: mounts and environment --------------------------------
# A fixture home stands in for the invoking user, so the contract paths are
# asserted without depending on this machine's real Pi setup.
contract_home="$tmpdir/contract-home"
invoked="$tmpdir/contract-invoked"
mkdir -p \
	"$contract_home/.pi/agent/extensions" \
	"$contract_home/.pi/agent/npm" \
	"$contract_home/.pi/agent/sessions" \
	"$contract_home/.agents/skills" \
	"$contract_home/.pi-lens" \
	"$contract_home/.config/herdr" \
	"$invoked"
touch "$contract_home/.gitconfig"
ssh_sock="$tmpdir/agent.sock"
python3 - "$ssh_sock" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
PY

reset_stubs
FAKE_IMAGES="$current_tag"
(
	export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 TERM=xterm-256color TZ=UTC
	SAFE_PI_TEST_HOME="$contract_home" \
		SAFE_PI_TEST_SSH=set SAFE_PI_TEST_SSH_SOCK="$ssh_sock" \
		SAFE_PI_TEST_HERDR=set \
		run_safe_pi --cwd "$invoked" -c
) || fail "contract run failed"

assert_log "--workdir $invoked"
assert_log "--volume $invoked:$invoked:rw"
assert_log "--volume $contract_home/.pi/agent:$contract_home/.pi/agent:rw"
assert_log "--volume $contract_home/.pi/agent/extensions:$contract_home/.pi/agent/extensions:ro"
assert_log "--volume $contract_home/.pi/agent/npm:$contract_home/.pi/agent/npm:ro"
assert_log "--volume $contract_home/.pi/agent/sessions:/run/safe-pi/sessions:rw"
assert_log "--volume $contract_home/.agents/skills:$contract_home/.agents/skills:ro"
assert_log "--volume $repo_root:$repo_root:ro"
assert_log "--volume $contract_home/.pi-lens:$contract_home/.pi-lens:rw"
assert_log "--volume $repo_root/mise/.config/mise:$contract_home/.config/mise:ro"
assert_log "--volume $contract_home/.config/herdr:$contract_home/.config/herdr:ro"
assert_log "--volume $contract_home/.gitconfig:$contract_home/.gitconfig:ro"
assert_log "--volume $ssh_sock:/run/safe-pi/ssh-agent.sock:rw"
assert_log "--volume safe-pi-toolchain-u$uid:$contract_home/.local/share/mise:rw"
assert_log "--tmpfs /tmp"
assert_log "--env SAFE_PI_SANDBOX=1"
for name in HOME USER LANG LC_ALL LC_CTYPE TERM TZ; do
	assert_log "--env $name"
done
assert_log "--env MISE_DATA_DIR=$contract_home/.local/share/mise"
# Mise's cache lives inside the toolchain volume, so per-start convergence
# does not re-resolve `latest` pins from a cold cache.
assert_log "--env MISE_CACHE_DIR=$contract_home/.local/share/mise/cache"
# Mise's state (incomplete-install tracking, trust) is persisted in the same
# volume: state kept in a throwaway container would let an interrupted install
# look complete on the next start.
assert_log "--env MISE_STATE_DIR=$contract_home/.local/share/mise/state"
encoded_invoked="${invoked#/}"
encoded_invoked="--${encoded_invoked//[\/\\:]/-}--"
assert_log "--env PI_CODING_AGENT_SESSION_DIR=/run/safe-pi/sessions/$encoded_invoked"
assert_log "--env SSH_AUTH_SOCK=/run/safe-pi/ssh-agent.sock"
# The reporter gets the socket and pane under sandbox-owned names; Herdr's own
# names are withheld so the Herdr-managed integration cannot activate.
assert_log "--env SAFE_PI_HERDR_SOCKET_PATH=/tmp/safe-pi-test-herdr.sock"
assert_log "--env SAFE_PI_HERDR_PANE_ID=wtest:p1"
assert_no_log "--env HERDR_"
assert_no_log "docker.sock"

# The Herdr and SSH variables are forwarded only when the host sets them.
reset_stubs
FAKE_IMAGES="$current_tag"
SAFE_PI_TEST_HOME="$contract_home" \
	SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	run_safe_pi --cwd "$invoked" -c || fail "contract run without Herdr or SSH failed"
assert_no_log "--env HERDR_"
assert_no_log "SSH_AUTH_SOCK"
assert_no_log "ssh-agent.sock"

# The checkout is not mounted read-only over itself when it is the working repo.
reset_stubs
FAKE_IMAGES="$current_tag"
SAFE_PI_TEST_HOME="$contract_home" \
	SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	run_safe_pi --cwd "$repo_root" -c || fail "checkout working-directory run failed"
assert_log "--volume $repo_root:$repo_root:rw"
assert_no_log "--volume $repo_root:$repo_root:ro"

# A working directory inside the checkout still gets the read-only checkout
# mount; the deeper read-write working-directory mount wins inside it.
reset_stubs
FAKE_IMAGES="$current_tag"
SAFE_PI_TEST_HOME="$contract_home" \
	SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	run_safe_pi --cwd "$repo_root/pi" -c || fail "checkout subdirectory run failed"
assert_log "--volume $repo_root:$repo_root:ro"
assert_log "--volume $repo_root/pi:$repo_root/pi:rw"

# A dry run prints the invocation without touching the host.
dry_home="$tmpdir/dry-home"
mkdir -p "$dry_home"
reset_stubs
SAFE_PI_TEST_HOME="$dry_home" \
	SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	run_safe_pi --dry-run -c >/dev/null || fail "dry run failed"
[[ ! -e "$dry_home/.pi" ]] || fail "dry run created \$HOME/.pi on the host"

# --- Prepare converges the declared environment and never starts Pi -------------

reset_stubs
FAKE_IMAGES="$current_tag"
run_safe_pi --prepare || fail "prepare run failed"
assert_log "docker run --rm"
assert_log "$current_tag --prepare"
assert_no_log " pi"
assert_no_log " bash"
[[ ! -s "$NPM_LOG" ]] || fail "prepare must not query npm"

# A failed convergence surfaces as the exit status.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_RUN_STATUS=1
status="$(status_of run_safe_pi --prepare)"
[[ "$status" == "1" ]] || fail "prepare must pass a convergence failure through, got $status"

# Prepare takes no Pi arguments and is not a shell.
reset_stubs
FAKE_IMAGES="$current_tag"
set +e
prepare_args_stderr="$(run_safe_pi --prepare -c 2>&1 >/dev/null)"
prepare_args_status=$?
set -e
[[ "$prepare_args_status" == "2" ]] || fail "prepare with Pi arguments should exit 2, got $prepare_args_status"
case "$prepare_args_stderr" in
*"--prepare"*) ;;
*) fail "prepare-with-arguments message not actionable: $prepare_args_stderr" ;;
esac
assert_no_log "docker run"

reset_stubs
FAKE_IMAGES="$current_tag"
set +e
run_safe_pi --prepare --shell >/dev/null 2>&1
prepare_shell_status=$?
set -e
[[ "$prepare_shell_status" == "2" ]] || fail "prepare with --shell should exit 2, got $prepare_shell_status"
assert_no_log "docker run"

# A dry run shows the prepare invocation without touching Docker.
reset_stubs
FAKE_IMAGES="$current_tag"
prepare_dry="$(run_safe_pi --dry-run --prepare)" || fail "prepare dry run failed"
[[ ! -s "$DOCKER_LOG" ]] || fail "prepare dry run must not invoke docker"
case "$prepare_dry" in
*"$current_tag --prepare"*) ;;
*) fail "prepare dry run output missing the prepare invocation: $prepare_dry" ;;
esac

printf 'safe-pi wrapper tests passed\n'
