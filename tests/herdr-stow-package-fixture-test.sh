#!/usr/bin/env bash
# The Stow test must pass even when its source checkout contains Herdr runtime.
# Exercise the real test entry point in a disposable checkout, never live state.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FIXTURE_ROOT="$TMP_DIR/checkout"
mkdir -p "$FIXTURE_ROOT/tests"

# Copy the current tracked package, including uncommitted edits, into a Git
# fixture. Runtime is added after staging so it stays machine-local.
git -C "$ROOT_DIR" ls-files -z -- herdr >"$TMP_DIR/package-files"
while IFS= read -r -d '' path; do
	mkdir -p "$FIXTURE_ROOT/$(dirname "$path")"
	cp -P "$ROOT_DIR/$path" "$FIXTURE_ROOT/$path"
done <"$TMP_DIR/package-files"
cp "$ROOT_DIR/tests/herdr-stow-package-test.sh" "$FIXTURE_ROOT/tests/"
git init -q "$FIXTURE_ROOT"
git -C "$FIXTURE_ROOT" add -- herdr tests/herdr-stow-package-test.sh

RUNTIME_ROOT="$FIXTURE_ROOT/herdr/.config/herdr"
AGENT_TARGET="/private/tmp/com.apple.launchd.fixture/Listeners"
ln -s "$AGENT_TARGET" "$RUNTIME_ROOT/herdr.sock.agent"
# Real sockets reproduce the other failure of copying a running checkout.
# Relative bind paths stay within macOS's Unix socket path-length limit.
python3 - "$RUNTIME_ROOT" <<'PY'
import os
import socket
import sys

os.chdir(sys.argv[1])
os.makedirs("sessions/demo")
for path in ("herdr.sock", "sessions/demo/herdr.sock"):
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(path)
PY

if ! bash "$FIXTURE_ROOT/tests/herdr-stow-package-test.sh" >"$TMP_DIR/result" 2>&1; then
	cat "$TMP_DIR/result" >&2
	printf 'FAIL: Herdr Stow test rejected a checkout with existing runtime\n' >&2
	exit 1
fi

[[ "$(readlink "$RUNTIME_ROOT/herdr.sock.agent")" == "$AGENT_TARGET" ]] || {
	printf 'FAIL: Herdr Stow test changed the source runtime link\n' >&2
	exit 1
}

[[ -S "$RUNTIME_ROOT/herdr.sock" && -S "$RUNTIME_ROOT/sessions/demo/herdr.sock" ]] || {
	printf 'FAIL: Herdr Stow test removed the source runtime sockets\n' >&2
	exit 1
}

printf 'herdr stow package fixture: ok\n'
