#!/usr/bin/env bash
# safe-pi entrypoint — converge the declared environment, then run the command.
#
# The image's entrypoint, so every sandbox start (Pi, the debug shell, or a
# prepare run) goes through the same convergence:
#
#   1. converges the environment declared in the mounted mise configuration, plus
#      the working repository's own pins, into the toolchain volume;
#   2. puts the declared tools' shims ahead of the image's own binaries;
#   3. before a Pi start, checks that the Node Pi will run on satisfies Pi's
#      engine requirement;
#   4. executes the command.
#
# Usage: safe-pi-entrypoint --prepare
#        safe-pi-entrypoint command [arguments...]
#
# --prepare converges strictly and exits without starting anything. A command
# converges fail-open: a failed convergence warns and the command still runs.
set -euo pipefail

readonly SCRIPT_NAME="safe-pi"
readonly CONVERGE_STEP="mise install --yes"

# Container-only paths the wrapper and this entrypoint share. The host
# extensions are mounted at HOST_EXTENSIONS_DIR, and the entrypoint builds the
# extensions view Pi discovers (EXTENSIONS_VIEW) from them.
readonly MANAGED_HERDR_EXTENSION="herdr-agent-state"
readonly HOST_EXTENSIONS_DIR="${SAFE_PI_HOST_EXTENSIONS:-/run/safe-pi/host-extensions}"
readonly SANDBOX_REPORTER="${SAFE_PI_REPORTER:-/usr/local/share/safe-pi/herdr-reporter.ts}"
readonly AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
readonly EXTENSIONS_VIEW="$AGENT_DIR/extensions"

warn() {
	printf '%s: warning: %s\n' "$SCRIPT_NAME" "$1" >&2
}

fail() {
	printf '%s: %s\n' "$SCRIPT_NAME" "$1" >&2
	exit 1
}

# --- Parse the invocation -----------------------------------------------------
prepare=0
if [[ "${1-}" == "--prepare" ]]; then
	prepare=1
	shift
	(($# == 0)) || fail "--prepare runs no command"
elif (($# == 0)); then
	fail "no command given; pass a command or --prepare"
fi

# Pi is the only command whose start is gated on its Node requirement. The
# image's npm is located before PATH changes, because the declared shims may
# shadow the npm that installed Pi.
run_pi=0
image_npm_root=""
if ((!prepare)) && [[ "${1-}" == "pi" ]]; then
	run_pi=1
	image_npm_root="$(npm root -g 2>/dev/null || true)"
fi

# --- Declared tools first on PATH ---------------------------------------------
MISE_DATA_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}"
export MISE_DATA_DIR
# Mise's cache and state belong in the volume too: state there is what lets an
# interrupted install be recognised on the next start.
export MISE_CACHE_DIR="${MISE_CACHE_DIR:-$MISE_DATA_DIR/cache}"
export MISE_STATE_DIR="${MISE_STATE_DIR:-$MISE_DATA_DIR/state}"
export PATH="$MISE_DATA_DIR/shims:$PATH"

# The working repository's own mise configuration is honoured because the
# sandbox is the boundary: Pi already runs whatever the repository contains.
export MISE_TRUSTED_CONFIG_PATHS="$PWD${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}"

# --- Converge the declared environment ------------------------------------------
# Converges the configuration that applies in DIR. The probe is silent and
# fast when everything is installed, so a steady start prints nothing; the
# install runs, with its progress, only when something is missing.
converge_in() {
	local dir="$1"
	(
		cd "$dir" || exit 1
		mise install --dry-run-code >/dev/null 2>&1 && exit 0
		mise install --yes
	)
}

# The volume may be converged by several containers at once. The lock
# serializes them, so the second one waits and then finds everything installed.
converge() {
	local lock="$MISE_DATA_DIR/.safe-pi-converge.lock" status=0
	mkdir -p "$MISE_DATA_DIR"
	(
		exec 9>"$lock"
		if ! flock -n 9; then
			printf '%s: waiting for another sandbox to finish converging the toolchain\n' "$SCRIPT_NAME" >&2
			flock 9
		fi
		# The declaration applies everywhere, so it converges from home. The
		# repository's own pins follow; where they override a declared tool, mise
		# installs the pinned version alongside the declared one. Both steps run
		# even if the first fails, so one failure does not hide the other.
		converge_in "$HOME" || status=1
		converge_in "$PWD" || status=1
		exit "$status"
	)
}

if ! converge; then
	if ((prepare)); then
		fail "toolchain convergence failed at '$CONVERGE_STEP'"
	fi
	warn "toolchain convergence failed at '$CONVERGE_STEP'; starting with the tools already in the volume"
fi

if ((prepare)); then
	exit 0
fi

# --- Pi's Node engine requirement ---------------------------------------------
# Pi runs on whichever `node` PATH resolves to (its shebang is `env node`), so
# the check uses that same node against the range in Pi's own package.json.
# npm bundles the semver module that evaluates the range.
check_pi_engine() {
	local npm_root="$1" pi_package="$1/@earendil-works/pi-coding-agent"
	local semver="$1/npm/node_modules/semver"
	if [[ -z "$npm_root" || ! -f "$pi_package/package.json" || ! -f "$semver/package.json" ]]; then
		warn "cannot read Pi's Node requirement; starting Pi without checking it"
		return 0
	fi
	node -e '
		const semver = require(process.argv[1]);
		const pkg = require(process.argv[2]);
		const name = process.argv[3];
		const range = pkg.engines && pkg.engines.node;
		if (!range || semver.satisfies(process.version, range)) process.exit(0);
		console.error(
			name + ": refusing to start Pi: node " + process.version +
			" does not satisfy the engine requirement of Pi " + pkg.version +
			" (node " + range + ")"
		);
		process.exit(1);
	' "$semver" "$pi_package/package.json" "$SCRIPT_NAME"
}

if ((run_pi)); then
	check_pi_engine "$image_npm_root" || exit 1
fi

# --- Sandbox extensions view ---------------------------------------------------
# The wrapper mounts the host extensions read-only at a container-only path and
# a tmpfs at the path Pi discovers, so this can build a view that keeps every
# host extension but replaces the Herdr-managed integration with the sandbox
# reporter. Herdr ignores the managed integration's `herdr:pi` report because a
# sandboxed pane's foreground process is `docker`, so dropping it leaves exactly
# one source owning the pane. Best effort: whatever fails here, the command
# still runs with the extensions that are already visible.
build_extensions_view() {
	[[ "${SAFE_PI_SANDBOX:-}" == "1" ]] || return 0
	mkdir -p "$EXTENSIONS_VIEW" 2>/dev/null || return 0

	local entry name
	if [[ -d "$HOST_EXTENSIONS_DIR" ]]; then
		for entry in "$HOST_EXTENSIONS_DIR"/*; do
			[[ -e "$entry" || -L "$entry" ]] || continue
			name="${entry##*/}"
			case "$name" in
			"$MANAGED_HERDR_EXTENSION".ts | "$MANAGED_HERDR_EXTENSION".js) continue ;;
			esac
			ln -sfn "$entry" "$EXTENSIONS_VIEW/$name" 2>/dev/null || true
		done
	fi

	if [[ -f "$SANDBOX_REPORTER" ]]; then
		ln -sfn "$SANDBOX_REPORTER" "$EXTENSIONS_VIEW/${SANDBOX_REPORTER##*/}" 2>/dev/null || true
	fi
}

build_extensions_view

exec "$@"
