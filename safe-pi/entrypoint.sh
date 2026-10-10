#!/usr/bin/env bash
# safe-pi entrypoint — converge the declared environment, then run the command.
#
# The image's entrypoint, so every sandbox start (Pi, the debug shell, or a
# prepare run) goes through the same convergence:
#
#   1. resolves the locale onto one the image can run UTF-8 under;
#   2. converges the environment declared in the mounted mise configuration, plus
#      the working repository's own pins, into the toolchain volume;
#   3. converges the sandbox package tree (Pi's npm packages) from the host's
#      package lock, so their native parts match the sandbox's platform;
#   4. puts the declared tools' shims ahead of the image's own binaries;
#   5. before a Pi start, checks that the Node Pi will run on satisfies Pi's
#      engine requirement;
#   6. executes the command.
#
# Usage: safe-pi-entrypoint --prepare
#        safe-pi-entrypoint command [arguments...]
#
# --prepare converges strictly and exits without starting anything. A command
# converges fail-open: a failed convergence warns and the command still runs.
# The two convergences are independent: one failing does not skip the other.
set -euo pipefail

readonly SCRIPT_NAME="safe-pi"
readonly CONVERGE_STEP="mise install --yes"
readonly NPM_CONVERGE_STEP="npm ci --legacy-peer-deps"

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

# --- The locale the sandbox runs under -----------------------------------------
# The wrapper forwards the host's locale as host identity, but the image only
# ships the locales it was built with: en_US.UTF-8, plus glibc's built-in
# C.UTF-8. glibc resolving a locale it does not have is not cosmetic — it warns
# on every locale-aware call and falls back to the POSIX charmap, which starts
# the Erlang VM with latin1 native name encoding and makes every `elixir`
# invocation warn, including the one mise runs while installing Elixir. So the
# sandbox runs under the host's locale when the image ships it and under C.UTF-8
# otherwise: always UTF-8, never POSIX by accident. This runs before
# convergence, so mise, the tools it installs, and the command itself all see
# the same locale.
locale_key() { # glibc matches locale names ignoring case and codeset punctuation
	printf '%s' "$1" | tr -d '[:punct:]' | tr '[:upper:]' '[:lower:]'
}

sandbox_locales="$(locale -a 2>/dev/null || true)"
for locale_var in LANG LC_ALL LC_CTYPE; do
	locale_value="${!locale_var-}"
	[[ -n "$locale_value" ]] || continue
	locale_wanted="$(locale_key "$locale_value")"
	# A locale naming no UTF-8 codeset (C, POSIX, a legacy latin1 name) is a
	# single-byte charmap whether or not the image ships it.
	if [[ "$locale_wanted" != *utf* ]]; then
		export "$locale_var=C.UTF-8"
		continue
	fi
	locale_honoured=0
	while IFS= read -r locale_entry; do
		if [[ "$(locale_key "$locale_entry")" == "$locale_wanted" ]]; then
			locale_honoured=1
			break
		fi
	done <<<"$sandbox_locales"
	((locale_honoured)) || export "$locale_var=C.UTF-8"
done

# --- Declared tools first on PATH ---------------------------------------------
# The package tree is installed with the image's own node and npm, so the PATH
# the image started with is kept before the shims shadow it.
IMAGE_PATH="$PATH"
MISE_DATA_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}"
export MISE_DATA_DIR
# Mise's cache and state belong in the volume too: state there is what lets an
# interrupted install be recognised on the next start.
export MISE_CACHE_DIR="${MISE_CACHE_DIR:-$MISE_DATA_DIR/cache}"
export MISE_STATE_DIR="${MISE_STATE_DIR:-$MISE_DATA_DIR/state}"
# Erlang/OTP: the image is Debian and mise publishes no precompiled OTP for it,
# so the declared OTP would be built from source — a 107 MB download plus a
# configure that fails on the image's missing build headers, on every start,
# because mise does not remember a failed install. The sandbox therefore asks
# for the Ubuntu 22.04 build, whose older glibc the image satisfies, and refuses
# the source fallback, so a pin without a precompiled build fails fast and loud
# instead of re-downloading. Both settings are sandbox-only: on the host,
# refusing the fallback would break the next OTP install outright.
export MISE_ERLANG_PRECOMPILED_OS="${MISE_ERLANG_PRECOMPILED_OS:-ubuntu-22.04}"
export MISE_ERLANG_COMPILE="${MISE_ERLANG_COMPILE:-false}"
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

# --- Converge the sandbox package tree -----------------------------------------
# Pi's npm packages carry one native binding per platform, and the host's tree
# holds only the host's (ADR 0009). The sandbox therefore keeps its own tree,
# installed here from the host's package.json and package-lock.json, which the
# wrapper mounts read-only. With no host lock nothing is declared, so there is
# nothing to converge.
SANDBOX_NPM_DIR="$HOME/.pi/agent/npm"
HOST_NPM_DIR="${SAFE_PI_HOST_NPM_DIR:-/run/safe-pi/host-npm}"
NPM_STAMP="$SANDBOX_NPM_DIR/.safe-pi-stamp"

# The key: the host's declaration plus the Node ABI the native parts are built
# for. A changed lock, or an image with another Node major, reinstalls.
npm_key() {
	local abi
	abi="$(node -p process.versions.modules)" || return 1
	node -e '
		const crypto = require("crypto");
		const fs = require("fs");
		const hash = crypto.createHash("sha256");
		hash.update("abi=" + process.argv[1] + "\0");
		for (const file of process.argv.slice(2)) hash.update(fs.readFileSync(file)).update("\0");
		process.stdout.write(hash.digest("hex"));
	' "$abi" "$HOST_NPM_DIR/package.json" "$HOST_NPM_DIR/package-lock.json"
}

npm_tree_converged() { # $1 = key
	[[ -f "$NPM_STAMP" && "$(cat "$NPM_STAMP" 2>/dev/null || true)" == "$1" ]]
}

# The tree may be converged by several containers at once. The lock serializes
# them, so the second one waits and then finds the tree converged. The stamp is
# removed before the install and written only after it succeeds, so an
# interrupted or failed install is retried on the next start.
converge_npm() {
	[[ -f "$HOST_NPM_DIR/package-lock.json" && -f "$HOST_NPM_DIR/package.json" ]] || return 0
	local key lock="$SANDBOX_NPM_DIR/.safe-pi-converge.lock"
	mkdir -p "$SANDBOX_NPM_DIR" || return 1
	key="$(npm_key)" || return 1
	npm_tree_converged "$key" && return 0
	(
		exec 9>"$lock"
		if ! flock -n 9; then
			printf '%s: waiting for another sandbox to finish installing the Pi packages\n' "$SCRIPT_NAME" >&2
			flock 9
		fi
		npm_tree_converged "$key" && exit 0
		rm -f "$NPM_STAMP"
		printf '%s: installing the Pi packages into the sandbox package tree\n' "$SCRIPT_NAME" >&2
		cp "$HOST_NPM_DIR/package.json" "$HOST_NPM_DIR/package-lock.json" "$SANDBOX_NPM_DIR/" || exit 1
		cd "$SANDBOX_NPM_DIR" || exit 1
		# Install scripts stay enabled: these are the packages the host already
		# trusted. --legacy-peer-deps is the flag Pi's own installs use, so the
		# lock is honoured.
		npm ci --legacy-peer-deps --no-fund --no-audit >&2 || exit 1
		printf '%s' "$key" >"$NPM_STAMP"
	)
}

converge_failed=0
if ! converge; then
	if ((prepare)); then
		printf "%s: toolchain convergence failed at '%s'\n" "$SCRIPT_NAME" "$CONVERGE_STEP" >&2
		converge_failed=1
	else
		warn "toolchain convergence failed at '$CONVERGE_STEP'; starting with the tools already in the volume"
	fi
fi
if ! (PATH="$IMAGE_PATH" converge_npm); then
	if ((prepare)); then
		printf "%s: package tree convergence failed at '%s'\n" "$SCRIPT_NAME" "$NPM_CONVERGE_STEP" >&2
		converge_failed=1
	else
		warn "package tree convergence failed at '$NPM_CONVERGE_STEP'; starting with the packages already in the tree"
	fi
fi

if ((prepare)); then
	exit "$converge_failed"
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

exec "$@"
