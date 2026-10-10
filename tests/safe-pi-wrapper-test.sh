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

# The suite plays the host. Inside the sandbox the marker is already set, and
# the wrapper's re-entry guard would then exec Pi directly instead of asking
# docker for a container. Clear it; the re-entry case sets it explicitly.
unset SAFE_PI_SANDBOX

BIN="$tmpdir/bin"
mkdir -p "$BIN"

DOCKER_LOG="$tmpdir/docker.log"
NPM_LOG="$tmpdir/npm.log"
SSH_LOG="$tmpdir/ssh.log"
PI_LOG="$tmpdir/pi.log"
: >"$DOCKER_LOG"
: >"$NPM_LOG"
: >"$SSH_LOG"
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
		if [[ "$*" == *"--format"* ]]; then
			printf '%s\n' "${SAFE_PI_FAKE_DAEMON_NAME:-colima}"
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
			elif [[ "$*" == *"safe-pi.home"* ]]; then
				printf '%s\n' "${SAFE_PI_FAKE_HOME_LABEL:-$HOME}"
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

# Stub the host OS: Linux unless a test plays the macOS host.
cat >"$BIN/uname" <<'UNAME'
#!/usr/bin/env bash
printf '%s\n' "${SAFE_PI_FAKE_UNAME:-Linux}"
UNAME
chmod +x "$BIN/uname"

# Stub the SSH client the macOS relay runs. It records every invocation. The
# master connection (-M) fails when SAFE_PI_FAKE_SSH_MASTER_FAIL is set; a
# forward whose host socket path contains SAFE_PI_FAKE_SSH_FORWARD_FAIL fails.
cat >"$BIN/ssh" <<'SSH'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh %s\n' "$*" >>"${SAFE_PI_SSH_LOG:?}"
if [[ " $* " == *" -M "* && -n "${SAFE_PI_FAKE_SSH_MASTER_FAIL-}" ]]; then
	printf '%s\n' "$SAFE_PI_FAKE_SSH_MASTER_FAIL" >&2
	exit 255
fi
if [[ "$*" == *"-O forward"* && -n "${SAFE_PI_FAKE_SSH_FORWARD_FAIL-}" && "$*" == *"${SAFE_PI_FAKE_SSH_FORWARD_FAIL}"* ]]; then
	printf 'forward refused\n' >&2
	exit 255
fi
exit 0
SSH
chmod +x "$BIN/ssh"

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
	: >"$SSH_LOG"
	: >"$PI_LOG"
	FAKE_UNAME="Linux"
	FAKE_DAEMON_NAME="colima"
	FAKE_HOME_LABEL=""
	FAKE_SSH_MASTER_FAIL=""
	FAKE_SSH_FORWARD_FAIL=""
	FAKE_IMAGES=""
	FAKE_PI_VERSION="1.1.0"
	FAKE_LATEST_PI="9.9.9"
	FAKE_DOCKER_UP=1
	FAKE_RUN_STATUS=0
	FAKE_HOST_PI_VERSION=""
	FAKE_ENTRYPOINT="9"
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
		sock) export HERDR_ENV=1 HERDR_SOCKET_PATH="${SAFE_PI_TEST_HERDR_SOCK-}" HERDR_PANE_ID=wtest:p1 ;;
		unset) unset HERDR_ENV HERDR_SOCKET_PATH HERDR_PANE_ID ;;
		esac
		if [[ -n "${SAFE_PI_TEST_PATH-}" ]]; then
			path="$SAFE_PI_TEST_PATH"
		else
			path="${SAFE_PI_TEST_BIN:-$BIN}:$PATH"
		fi
		SAFE_PI_DOCKER_LOG="$DOCKER_LOG" \
			SAFE_PI_NPM_LOG="$NPM_LOG" \
			SAFE_PI_SSH_LOG="$SSH_LOG" \
			SAFE_PI_FAKE_UNAME="${FAKE_UNAME-Linux}" \
			SAFE_PI_FAKE_DAEMON_NAME="${FAKE_DAEMON_NAME-colima}" \
			SAFE_PI_FAKE_HOME_LABEL="${FAKE_HOME_LABEL-}" \
			SAFE_PI_FAKE_SSH_MASTER_FAIL="${FAKE_SSH_MASTER_FAIL-}" \
			SAFE_PI_FAKE_SSH_FORWARD_FAIL="${FAKE_SSH_FORWARD_FAIL-}" \
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
assert_log "--mount type=bind,source=$PWD,target=$PWD"
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
assert_log "--mount type=bind,source=$invoked,target=$invoked"
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
printf '{}\n' >"$contract_home/.pi/agent/npm/package.json"
printf '{}\n' >"$contract_home/.pi/agent/npm/package-lock.json"
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
assert_log "--mount type=bind,source=$invoked,target=$invoked"
assert_log "--mount type=bind,source=$contract_home/.pi/agent,target=$contract_home/.pi/agent"
assert_log "--mount type=bind,source=$contract_home/.pi/agent/extensions,target=$contract_home/.pi/agent/extensions,readonly"
# The sandbox keeps its own package tree (ADR 0009): a directory private to the
# sandbox is bound where Pi looks for its packages, and the host's tree is not
# reachable. Only the host's declaration is mounted, read-only, at a
# container-only path, for the entrypoint to install from.
assert_log "--mount type=bind,source=$contract_home/.cache/safe-pi/npm,target=$contract_home/.pi/agent/npm"
assert_no_log "source=$contract_home/.pi/agent/npm,target=$contract_home/.pi/agent/npm"
assert_log "--mount type=bind,source=$contract_home/.pi/agent/npm/package.json,target=/run/safe-pi/host-npm/package.json,readonly"
assert_log "--mount type=bind,source=$contract_home/.pi/agent/npm/package-lock.json,target=/run/safe-pi/host-npm/package-lock.json,readonly"
[[ -d "$contract_home/.cache/safe-pi/npm" ]] ||
	fail "the sandbox package tree directory must be created as the invoking user"
assert_log "--mount type=bind,source=$contract_home/.pi/agent/sessions,target=/run/safe-pi/sessions"
assert_log "--mount type=bind,source=$contract_home/.agents/skills,target=$contract_home/.agents/skills,readonly"
assert_log "--mount type=bind,source=$repo_root,target=$repo_root,readonly"
assert_log "--mount type=bind,source=$contract_home/.pi-lens,target=$contract_home/.pi-lens"
assert_log "--mount type=bind,source=$repo_root/mise/.config/mise,target=$contract_home/.config/mise,readonly"
assert_log "--mount type=bind,source=$contract_home/.config/herdr,target=$contract_home/.config/herdr,readonly"
assert_log "--mount type=bind,source=$contract_home/.gitconfig,target=$contract_home/.gitconfig,readonly"
assert_log "--mount type=bind,source=$ssh_sock,target=/run/safe-pi/ssh-agent.sock"
assert_log "--volume safe-pi-toolchain-u$uid:$contract_home/.local/share/mise:rw"
# The extension transpile cache is bound over the throwaway temporary directory,
# because jiti caches the compiled extensions under `/tmp`, which the sandbox
# would otherwise discard on every start. It is the sandbox's own directory, not
# the host Pi's: a cache entry is a module the host Pi executes.
assert_log "--mount type=bind,source=$contract_home/.cache/safe-pi/jiti,target=/tmp/jiti"
assert_log "--tmpfs /tmp"
[[ -d "$contract_home/.cache/safe-pi/jiti" ]] ||
	fail "the transpile cache directory must be created as the invoking user"
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
assert_log "--mount type=bind,source=$repo_root,target=$repo_root"
assert_no_log "--volume $repo_root:$repo_root:ro"

# A working directory inside the checkout still gets the read-only checkout
# mount; the deeper read-write working-directory mount wins inside it.
reset_stubs
FAKE_IMAGES="$current_tag"
SAFE_PI_TEST_HOME="$contract_home" \
	SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	run_safe_pi --cwd "$repo_root/pi" -c || fail "checkout subdirectory run failed"
assert_log "--mount type=bind,source=$repo_root,target=$repo_root,readonly"
assert_log "--mount type=bind,source=$repo_root/pi,target=$repo_root/pi"

# A host with no lock has nothing to declare: the sandbox package tree is still
# bound, and nothing is mounted from the host's tree.
nolock_home="$tmpdir/nolock-home"
mkdir -p "$nolock_home/.pi/agent/npm" "$nolock_home/.pi/agent/sessions"
printf '{}\n' >"$nolock_home/.pi/agent/npm/package.json"
reset_stubs
FAKE_IMAGES="$current_tag"
SAFE_PI_TEST_HOME="$nolock_home" \
	SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	run_safe_pi --cwd "$invoked" -c || fail "run without a host lock failed"
assert_log "--mount type=bind,source=$nolock_home/.cache/safe-pi/npm,target=$nolock_home/.pi/agent/npm"
assert_log "target=/run/safe-pi/host-npm/package.json,readonly"
assert_no_log "target=/run/safe-pi/host-npm/package-lock.json"
rm -f "$nolock_home/.pi/agent/npm/package.json"
reset_stubs
FAKE_IMAGES="$current_tag"
SAFE_PI_TEST_HOME="$nolock_home" \
	SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	run_safe_pi --cwd "$invoked" -c || fail "run without a host package tree failed"
assert_log "--mount type=bind,source=$nolock_home/.cache/safe-pi/npm,target=$nolock_home/.pi/agent/npm"
assert_no_log "target=/run/safe-pi/host-npm"

# A dry run shows the package tree mounts and still creates nothing.
dry_lock_home="$tmpdir/dry-lock-home"
mkdir -p "$dry_lock_home/.pi/agent/npm"
printf '{}\n' >"$dry_lock_home/.pi/agent/npm/package.json"
printf '{}\n' >"$dry_lock_home/.pi/agent/npm/package-lock.json"
reset_stubs
dry_lock="$(SAFE_PI_TEST_HOME="$dry_lock_home" \
	SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	run_safe_pi --dry-run -c)" || fail "dry run with a host lock failed"
dry_lock="${dry_lock//\\/}" # the dry run shell-quotes the commas inside --mount
grep -Fq "source=$dry_lock_home/.cache/safe-pi/npm,target=$dry_lock_home/.pi/agent/npm" <<<"$dry_lock" ||
	fail "the dry run must show the package tree mount: $dry_lock"
grep -Fq "target=/run/safe-pi/host-npm/package-lock.json,readonly" <<<"$dry_lock" ||
	fail "the dry run must show the host's lock mount: $dry_lock"
[[ ! -e "$dry_lock_home/.cache" ]] || fail "dry run created the sandbox package tree directory"

# A dry run prints the invocation without touching the host.
dry_home="$tmpdir/dry-home"
mkdir -p "$dry_home"
reset_stubs
SAFE_PI_TEST_HOME="$dry_home" \
	SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	run_safe_pi --dry-run -c >/dev/null || fail "dry run failed"
[[ ! -e "$dry_home/.pi" ]] || fail "dry run created \$HOME/.pi on the host"
[[ ! -e "$dry_home/.cache" ]] || fail "dry run created \$HOME/.cache on the host"

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

# --- The image's home is the host's ---------------------------------------------

# The sandbox user's home is the host's $HOME, passed as a build argument and
# recorded in a label; the label is what lets a wrapper tell a stale image.
reset_stubs
run_safe_pi -c || fail "build run failed"
assert_log "--build-arg USER_HOME=$HOME"
grep -Fq 'safe-pi.home="${USER_HOME}"' "$repo_root/safe-pi/Dockerfile" ||
	fail "the Dockerfile must record the sandbox user's home in the safe-pi.home label"
grep -Fq 'ENV HOME=${USER_HOME}' "$repo_root/safe-pi/Dockerfile" ||
	fail "the Dockerfile must give the sandbox user the build argument's home"

# An image built for another home is stale and rebuilt, with the reason said.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_HOME_LABEL="/home/someone-else"
run_safe_pi -c 2>"$tmpdir/stale-home.err" || fail "stale-home image run failed"
assert_log "docker build --tag $current_tag"
assert_log "--build-arg USER_HOME=$HOME"
assert_log "docker run --rm"
grep -Fq "home" "$tmpdir/stale-home.err" || fail "stale-home rebuild should say why"

# An image built for this home is kept.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_HOME_LABEL="$HOME"
run_safe_pi -c || fail "matching-home image run failed"
assert_no_log "docker build"

# --- Binds are `--mount type=bind`; volumes and the tmpfs keep their form -------

reset_stubs
FAKE_IMAGES="$current_tag"
run_safe_pi -c || fail "mount form run failed"
assert_no_log "--volume $PWD"
assert_log "--volume safe-pi-toolchain-u$uid:"
assert_log "--tmpfs /tmp"
# A comma would split a --mount argument, so the field is quoted.
comma_dir="$tmpdir/with,comma"
mkdir -p "$comma_dir"
reset_stubs
FAKE_IMAGES="$current_tag"
run_safe_pi --cwd "$comma_dir" -c || fail "comma working directory run failed"
assert_log "--mount type=bind,\"source=$comma_dir\",\"target=$comma_dir\""

# --- macOS: sockets reach the Colima VM over a relay ----------------------------

mac_home="$tmpdir/mac-home"
relay_tmp="$tmpdir/relay-tmp"
herdr_sock="$tmpdir/herdr.sock"
mkdir -p "$mac_home/.pi/agent" "$relay_tmp"
python3 - "$herdr_sock" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
PY
ssh_config="$mac_home/.colima/ssh_config"

run_mac() { # [args...]; the invoking shell has an agent and a Herdr pane
	TMPDIR="$relay_tmp" SAFE_PI_TEST_HOME="$mac_home" \
		SAFE_PI_TEST_SSH=set SAFE_PI_TEST_SSH_SOCK="$ssh_sock" \
		SAFE_PI_TEST_HERDR=sock SAFE_PI_TEST_HERDR_SOCK="$herdr_sock" \
		run_safe_pi "$@"
}

assert_ssh() {
	grep -Fq -- "$1" "$SSH_LOG" || {
		printf 'ssh log:\n' >&2
		cat "$SSH_LOG" >&2
		fail "expected ssh log to contain: $1"
	}
}

# The private directory the relay uses inside the VM, from the mkdir it ran.
relay_vm_dir() {
	grep -o 'mkdir -m 0700 -- /tmp/safe-pi\.[A-Za-z0-9]*' "$SSH_LOG" | head -1 | grep -o '/tmp/safe-pi\..*'
}

# Linux is unchanged: the agent socket is bind-mounted by path and no relay runs.
reset_stubs
FAKE_IMAGES="$current_tag"
run_mac -c || fail "Linux run with an agent failed"
assert_log "--mount type=bind,source=$ssh_sock,target=/run/safe-pi/ssh-agent.sock"
[[ ! -s "$SSH_LOG" ]] || fail "Linux must not open a relay"
assert_no_log "docker info --format"

# Darwin with the default Colima profile.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
run_mac -c || fail "Darwin run failed"
assert_log "docker info --format"
assert_ssh "-F $ssh_config"
# The sandbox's own connection: its own control path, in the background.
assert_ssh "-M -S $relay_tmp/"
assert_ssh " -f -N "
assert_ssh " colima"
vm_dir="$(relay_vm_dir)" || fail "the relay never created its directory in the VM"
assert_ssh "-O forward -R $vm_dir/ssh-agent.sock:$ssh_sock colima"
assert_ssh "-O forward -R $vm_dir/herdr.sock:$herdr_sock colima"
# The forwarded sockets are mounted at the paths the contract already uses.
assert_log "--mount type=bind,source=$vm_dir/ssh-agent.sock,target=/run/safe-pi/ssh-agent.sock"
assert_log "--mount type=bind,source=$vm_dir/herdr.sock,target=/run/safe-pi/herdr.sock"
assert_log "--env SSH_AUTH_SOCK=/run/safe-pi/ssh-agent.sock"
# The reporter's socket is the relayed one, at a container-only path: the host
# path sits in the shared home, where the daemon cannot mount over a socket.
assert_log "--env SAFE_PI_HERDR_SOCKET_PATH=/run/safe-pi/herdr.sock"
assert_log "--env SAFE_PI_HERDR_PANE_ID=wtest:p1"
assert_no_log "source=$ssh_sock"
assert_no_log "--volume $PWD"
# The connection and its directory are closed when the sandbox exits.
assert_ssh "rm -rf -- $vm_dir"
assert_ssh "-O exit colima"
[[ -z "$(ls -A "$relay_tmp")" ]] || fail "the relay's host directory must be removed on exit"
# The connection is the relay's first command, opened before the image checks.
first_ssh="$(head -1 "$SSH_LOG")"
case "$first_ssh" in
*" -M "*) ;;
*) fail "the master connection must be the relay's first command: $first_ssh" ;;
esac

# A named Colima profile is the Host alias in ~/.colima/ssh_config.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
FAKE_DAEMON_NAME=colima-work
run_mac -c || fail "Darwin named-profile run failed"
assert_ssh " colima-work"
assert_ssh "-O forward -R $(relay_vm_dir)/ssh-agent.sock:$ssh_sock colima-work"
assert_ssh "-O exit colima-work"

# The debug shell relays too, and lists the relayed mount points.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
run_mac --shell || fail "Darwin shell run failed"
assert_ssh "-O forward -R $(relay_vm_dir)/ssh-agent.sock:$ssh_sock colima"
assert_log "/run/safe-pi/ssh-agent.sock"

# Another daemon on macOS is refused, before anything starts.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
FAKE_DAEMON_NAME="Docker Desktop"
set +e
refuse_stderr="$(run_mac -c 2>&1 >/dev/null)"
refuse_status=$?
set -e
[[ "$refuse_status" == "2" ]] || fail "another macOS daemon should exit 2, got $refuse_status"
case "$refuse_stderr" in
*"safe-pi on macOS supports Colima only"*) ;;
*) fail "the refusal must say Colima only: $refuse_stderr" ;;
esac
assert_no_log "docker run"
assert_no_log "docker build"
[[ ! -s "$SSH_LOG" ]] || fail "a refused daemon must not open a relay"
# --prepare is refused on another daemon too: the daemon is what is unsupported.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
FAKE_DAEMON_NAME="Docker Desktop"
[[ "$(status_of run_mac --prepare 2>/dev/null)" == "2" ]] || fail "--prepare on another macOS daemon should exit 2"

# Without an agent or a Herdr pane there is nothing to relay.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
TMPDIR="$relay_tmp" SAFE_PI_TEST_HOME="$mac_home" SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	run_safe_pi -c || fail "Darwin run without sockets failed"
[[ ! -s "$SSH_LOG" ]] || fail "no sockets, no relay"
assert_no_log "ssh-agent.sock"

# A relay that cannot be opened is a warning per socket, and the sandbox starts
# without the sockets.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
FAKE_SSH_MASTER_FAIL="ssh: connect to host 127.0.0.1 port 51234: Connection refused"
set +e
run_mac -c 2>"$tmpdir/relay-fail.err"
relay_fail_status=$?
set -e
[[ "$relay_fail_status" == "0" ]] || fail "a failed relay must not block the sandbox, got $relay_fail_status"
grep -Fq "safe-pi: SSH agent unavailable in the sandbox: ssh: connect to host 127.0.0.1 port 51234: Connection refused" "$tmpdir/relay-fail.err" ||
	fail "missing the SSH agent warning: $(cat "$tmpdir/relay-fail.err")"
grep -Fq "safe-pi: Herdr socket unavailable in the sandbox: ssh: connect to host" "$tmpdir/relay-fail.err" ||
	fail "missing the Herdr warning: $(cat "$tmpdir/relay-fail.err")"
assert_log "docker run --rm"
assert_no_log "ssh-agent.sock"
assert_no_log "herdr.sock"
assert_no_log "--env SSH_AUTH_SOCK"
assert_no_log "--env SAFE_PI_HERDR_SOCKET_PATH"
[[ -z "$(ls -A "$relay_tmp")" ]] || fail "a failed relay must still clean up after itself"

# One socket failing leaves the other relayed.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
FAKE_SSH_FORWARD_FAIL="herdr.sock"
run_mac -c 2>"$tmpdir/herdr-fail.err" || fail "a failed Herdr forward must not block the sandbox"
grep -Fq "safe-pi: Herdr socket unavailable in the sandbox: forward refused" "$tmpdir/herdr-fail.err" ||
	fail "missing the Herdr warning: $(cat "$tmpdir/herdr-fail.err")"
if grep -Fq "SSH agent unavailable" "$tmpdir/herdr-fail.err"; then
	fail "the SSH agent was relayed and must not be reported"
fi
assert_log "target=/run/safe-pi/ssh-agent.sock"
assert_no_log "herdr.sock"

# A dry run prints the relay before the Docker invocation, and runs neither.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
mac_dry="$(run_mac --dry-run -c)" || fail "Darwin dry run failed"
[[ ! -s "$SSH_LOG" ]] || fail "a dry run must not run the relay"
assert_no_log "docker run"
assert_no_log "docker build"
relay_line="$(grep -n -- "-O forward -R .*/ssh-agent.sock:$ssh_sock colima" <<<"$mac_dry" | head -1 | cut -d: -f1)"
docker_line="$(grep -n "^docker run --rm" <<<"$mac_dry" | head -1 | cut -d: -f1)"
[[ -n "$relay_line" && -n "$docker_line" && "$relay_line" -lt "$docker_line" ]] ||
	fail "the dry run must print the relay before the Docker invocation: $mac_dry"
grep -Fq -- "-M -S" <<<"$mac_dry" || fail "the dry run must print the connection: $mac_dry"
grep -Fq -- "target=/run/safe-pi/ssh-agent.sock" <<<"$mac_dry" ||
	fail "the dry run must print the relayed mount: $mac_dry"
[[ -z "$(ls -A "$relay_tmp")" ]] || fail "a dry run must not leave a relay directory behind"

# The refusal holds for a dry run too, even with nothing to relay.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
FAKE_DAEMON_NAME="Docker Desktop"
[[ "$(status_of run_mac --dry-run 2>/dev/null)" == "2" ]] || fail "a dry run on another macOS daemon should exit 2"
reset_stubs
FAKE_UNAME=Darwin
FAKE_DAEMON_NAME="Docker Desktop"
TMPDIR="$relay_tmp" SAFE_PI_TEST_HOME="$mac_home" SAFE_PI_TEST_SSH=unset SAFE_PI_TEST_HERDR=unset \
	status_of run_safe_pi --dry-run >"$tmpdir/dry-refuse.status" 2>/dev/null || true
[[ "$(cat "$tmpdir/dry-refuse.status")" == "2" ]] || fail "a socketless dry run on another macOS daemon should exit 2"

# The dry run prints the options the real relay runs with.
grep -Fq -- "-o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR" <<<"$mac_dry" ||
	fail "the dry run must print the relay's ssh options: $mac_dry"

# --prepare opens no relay.
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
run_mac --prepare 2>"$tmpdir/mac-prepare.err" || fail "Darwin prepare run failed"
[[ ! -s "$tmpdir/mac-prepare.err" ]] || fail "--prepare must not warn about sockets: $(cat "$tmpdir/mac-prepare.err")"
[[ ! -s "$SSH_LOG" ]] || fail "--prepare must not open a relay"
assert_log "$current_tag --prepare"
reset_stubs
FAKE_IMAGES="$current_tag"
FAKE_UNAME=Darwin
mac_prepare_dry="$(run_mac --dry-run --prepare)" || fail "Darwin prepare dry run failed"
case "$mac_prepare_dry" in
*"-O forward"*) fail "the prepare dry run must not print a relay: $mac_prepare_dry" ;;
esac

printf 'safe-pi wrapper tests passed\n'
