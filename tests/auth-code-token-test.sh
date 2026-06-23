#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/auth-code-token"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

run_auth_code_token() {
	local stdout="$1"
	shift
	python - "$SCRIPT" "$@" >"$stdout" <<'PY'
import importlib.machinery
import importlib.util
import sys

script = sys.argv[1]
args = sys.argv[2:]
loader = importlib.machinery.SourceFileLoader('auth_code_token', script)
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

module.serve_callback = lambda port, path, state, timeout: 'auth-code'
module.post_form = lambda url, data: {
    'access_token': 'abc123',
    'refresh_token': 'refresh456',
    'token_type': 'Bearer',
    'expires_in': 3600,
}
module.webbrowser.open = lambda url: True

module.main(args)
PY
}

BASE_ARGS=(
	my-client
	https://auth.example/authorize
	https://auth.example/token
	--redirect-uri
	http://127.0.0.1:8765/callback
)

run_auth_code_token "$TMPDIR/default-stdout" "${BASE_ARGS[@]}"
if [ "$(cat "$TMPDIR/default-stdout")" != "abc123" ]; then
	echo "Expected default stdout to contain only access_token" >&2
	cat "$TMPDIR/default-stdout" >&2
	exit 1
fi

run_auth_code_token "$TMPDIR/json-stdout" "${BASE_ARGS[@]}" --json
python - "$TMPDIR/json-stdout" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

expected = {
    'access_token': 'abc123',
    'refresh_token': 'refresh456',
    'token_type': 'Bearer',
    'expires_in': 3600,
}
if data != expected:
    print('Expected stdout to contain full token response JSON', file=sys.stderr)
    print(data, file=sys.stderr)
    sys.exit(1)
PY
