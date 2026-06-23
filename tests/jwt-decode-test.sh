#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/jwt-decode"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

run_ok() {
	local name="$1"
	shift
	"$SCRIPT" "$@" >"$TMPDIR/${name}.out" 2>"$TMPDIR/${name}.err"
}

run_fail() {
	local name="$1"
	shift
	set +e
	"$SCRIPT" "$@" >"$TMPDIR/${name}.out" 2>"$TMPDIR/${name}.err"
	status=$?
	set -e
	if [ "$status" -eq 0 ]; then
		echo "Expected failure for $name" >&2
		exit 1
	fi
}

TOKEN_OK='eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjMiLCJuYW1lIjoiSm9obiBEb2UifQ.'
TOKEN_BAD_JSON='eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.bm90LWpzb24.'
TOKEN_BAD_SHAPE='not-a-jwt'

run_ok success "$TOKEN_OK"
python3 - "$TMPDIR/success.out" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

expected = {
    'sub': '123',
    'name': 'John Doe',
}
if data != expected:
    print('Decoded payload mismatch', file=sys.stderr)
    print(data, file=sys.stderr)
    sys.exit(1)
PY

run_fail usage
if ! grep -Fq 'Usage: jwt-decode <token>' "$TMPDIR/usage.err"; then
	echo 'Expected usage message on missing arg' >&2
	exit 1
fi

run_fail malformed "$TOKEN_BAD_SHAPE"
if ! grep -Fq 'Error: invalid JWT' "$TMPDIR/malformed.err"; then
	echo 'Expected invalid JWT error' >&2
	exit 1
fi

run_fail bad-json "$TOKEN_BAD_JSON"
if ! grep -Fq 'Error: invalid JWT payload JSON' "$TMPDIR/bad-json.err"; then
	echo 'Expected invalid JSON payload error' >&2
	exit 1
fi
