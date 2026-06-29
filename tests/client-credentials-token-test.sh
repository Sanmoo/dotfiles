#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/client-credentials-token"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Run the script with a stubbed `curl` that records its arguments to
# $TMPDIR/<name>.curl-args and returns a fixed access_token JSON.
# Returns 0 on success regardless of script exit status; the helper
# stores the exit status in $TMPDIR/<name>.status for later assertions.
run_scenario() {
	local name="$1"
	shift
	local stub_dir="$TMPDIR/${name}.bin"
	local curl_args_file="$TMPDIR/${name}.curl-args"
	local stdout_file="$TMPDIR/${name}.out"
	local stderr_file="$TMPDIR/${name}.err"
	local status_file="$TMPDIR/${name}.status"
	mkdir -p "$stub_dir"
	cat >"$stub_dir/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CURL_ARGS_FILE"
printf '{"access_token":"abc123","token_type":"Bearer"}\n'
STUB
	chmod +x "$stub_dir/curl"
	set +e
	CURL_ARGS_FILE="$curl_args_file" \
		PATH="$stub_dir:$PATH" \
		"$SCRIPT" "$@" \
		>"$stdout_file" 2>"$stderr_file"
	echo $? >"$status_file"
	set -e
}

assert_status() {
	local name="$1"
	local expected="$2"
	local got
	got="$(cat "$TMPDIR/${name}.status")"
	if [ "$got" -ne "$expected" ]; then
		echo "Expected $name to exit $expected, got $got" >&2
		echo "--- stderr ---" >&2
		cat "$TMPDIR/${name}.err" >&2
		exit 1
	fi
}

assert_stdout_is_token() {
	local name="$1"
	local got
	got="$(cat "$TMPDIR/${name}.out")"
	if [ "$got" != "abc123" ]; then
		echo "Expected $name stdout to be the access_token" >&2
		cat "$TMPDIR/${name}.out" >&2
		exit 1
	fi
}

assert_curl_has() {
	local name="$1"
	local needle="$2"
	local args_file="$TMPDIR/${name}.curl-args"
	if [ ! -f "$args_file" ]; then
		echo "Expected $name to invoke curl (args file missing)" >&2
		exit 1
	fi
	if ! grep -qF -- "$needle" "$args_file"; then
		echo "Expected $name curl args to contain: $needle" >&2
		echo "--- captured args ---" >&2
		cat "$args_file" >&2
		exit 1
	fi
}

assert_curl_lacks() {
	local name="$1"
	local needle="$2"
	local args_file="$TMPDIR/${name}.curl-args"
	if [ ! -f "$args_file" ]; then
		echo "Expected $name to invoke curl (args file missing)" >&2
		exit 1
	fi
	if grep -qF -- "$needle" "$args_file"; then
		echo "Expected $name curl args to NOT contain: $needle" >&2
		echo "--- captured args ---" >&2
		cat "$args_file" >&2
		exit 1
	fi
}

# --- Scenario 1: 3 args, no scope (existing behavior, regression) ---
run_scenario default my-client my-secret https://auth.example/token
assert_status default 0
assert_stdout_is_token default
assert_curl_has default "grant_type=client_credentials"
assert_curl_has default "client_id=my-client"
assert_curl_has default "client_secret=my-secret"
assert_curl_has default "https://auth.example/token"
assert_curl_lacks default "--user"
assert_curl_lacks default "scope="
assert_curl_lacks default "--data-urlencode"

# --- Scenario 2: 4 args with a non-empty scope ---
run_scenario with-scope my-client my-secret https://auth.example/token "read write"
assert_status with-scope 0
assert_stdout_is_token with-scope
assert_curl_has with-scope "scope=read write"
# --data-urlencode must be the curl flag (the value is sent as form data)
assert_curl_has with-scope "--data-urlencode"

# --- Scenario 3: 4 args with an empty scope (explicit empty) ---
run_scenario empty-scope my-client my-secret https://auth.example/token ""
assert_status empty-scope 0
assert_stdout_is_token empty-scope
assert_curl_lacks empty-scope "scope="

# --- Scenario 4: 4 args with a whitespace-only scope ---
run_scenario whitespace-scope my-client my-secret https://auth.example/token "   "
assert_status whitespace-scope 0
assert_stdout_is_token whitespace-scope
assert_curl_lacks whitespace-scope "scope="
