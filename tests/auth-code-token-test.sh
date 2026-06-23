#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/auth-code-token"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

run_auth_code_token() {
	local name="$1"
	shift
	AUTH_URL_CAPTURE="$TMPDIR/${name}.auth-url" \
		python - "$SCRIPT" "$@" >"$TMPDIR/${name}.out" 2>"$TMPDIR/${name}.err" <<'PY'
import importlib.machinery
import importlib.util
import os
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

def capture_open(url):
    with open(os.environ['AUTH_URL_CAPTURE'], 'w', encoding='utf-8') as f:
        f.write(url)
    return True

module.webbrowser.open = capture_open
module.main(args)
PY
}

run_fail() {
	local name="$1"
	shift
	set +e
	run_auth_code_token "$name" "$@"
	status=$?
	set -e
	if [ "$status" -eq 0 ]; then
		echo "Expected failure for $name" >&2
		exit 1
	fi
}

assert_query_value() {
	local url_file="$1"
	local key="$2"
	local expected="$3"
	python3 - "$url_file" "$key" "$expected" <<'PY'
import sys
from urllib.parse import parse_qs, urlparse

with open(sys.argv[1], encoding='utf-8') as f:
    url = f.read().strip()
key = sys.argv[2]
expected = sys.argv[3]
values = parse_qs(urlparse(url).query, keep_blank_values=True).get(key)
if values != [expected]:
    print(f'Expected {key}={expected!r}, got {values!r}', file=sys.stderr)
    sys.exit(1)
PY
}

BASE_ARGS=(
	my-client
	https://auth.example/authorize
	https://auth.example/token
	--redirect-uri
	http://127.0.0.1:8765/callback
)

run_auth_code_token default "${BASE_ARGS[@]}"
if [ "$(cat "$TMPDIR/default.out")" != "abc123" ]; then
	echo "Expected default stdout to contain only access_token" >&2
	cat "$TMPDIR/default.out" >&2
	exit 1
fi
assert_query_value "$TMPDIR/default.auth-url" response_type code
assert_query_value "$TMPDIR/default.auth-url" client_id my-client

run_auth_code_token json "${BASE_ARGS[@]}" --json
python3 - "$TMPDIR/json.out" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as f:
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

run_auth_code_token force-login "${BASE_ARGS[@]}" --force-login
assert_query_value "$TMPDIR/force-login.auth-url" prompt login
assert_query_value "$TMPDIR/force-login.auth-url" max_age 0

run_auth_code_token override "${BASE_ARGS[@]}" \
	--force-login \
	--auth-param prompt=select_account \
	--auth-param max_age=3600 \
	--auth-param audience=https://api.example
assert_query_value "$TMPDIR/override.auth-url" prompt select_account
assert_query_value "$TMPDIR/override.auth-url" max_age 3600
assert_query_value "$TMPDIR/override.auth-url" audience https://api.example

run_fail malformed-auth-param "${BASE_ARGS[@]}" --auth-param prompt
if ! grep -Fq 'Error: --auth-param must use key=value format' "$TMPDIR/malformed-auth-param.err"; then
	echo 'Expected malformed --auth-param error' >&2
	cat "$TMPDIR/malformed-auth-param.err" >&2
	exit 1
fi

run_fail protected-param "${BASE_ARGS[@]}" --auth-param state=override
if ! grep -Fq "Error: --auth-param cannot override reserved parameter 'state'" "$TMPDIR/protected-param.err"; then
	echo 'Expected protected parameter rejection' >&2
	cat "$TMPDIR/protected-param.err" >&2
	exit 1
fi
