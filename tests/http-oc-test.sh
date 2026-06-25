#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/http"

assert_contains() {
	local haystack="$1" needle="$2" message="$3"
	if ! grep -Fq -- "$needle" "$haystack"; then
		echo "FAIL: $message" >&2
		echo "  expected to find: $needle" >&2
		echo "  in:" >&2
		sed 's/^/    /' "$haystack" >&2
		exit 1
	fi
}

assert_not_contains() {
	local haystack="$1" needle="$2" message="$3"
	if grep -Fq -- "$needle" "$haystack"; then
		echo "FAIL: $message" >&2
		echo "  expected not to find: $needle" >&2
		echo "  in:" >&2
		sed 's/^/    /' "$haystack" >&2
		exit 1
	fi
}

setup_oc_tmp() {
	OC_TMPDIR="$(mktemp -d)"
	OC_HOME="$OC_TMPDIR/home"
	OC_BIN="$OC_TMPDIR/bin"
	OC_ROOT="$OC_TMPDIR/collections"
	mkdir -p "$OC_HOME/.config" "$OC_BIN" "$OC_ROOT"
	cat >"$OC_BIN/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CURL_ARGS_FILE"
printf '{"access_token":"stub-token","token_type":"Bearer","expires_in":3600}\n'
STUB
	chmod +x "$OC_BIN/curl"
	cat >"$OC_HOME/.config/.httprc" <<EOF_RC
collections:
  - $OC_ROOT
EOF_RC
}

run_http_oc() {
	local tmp_stdout tmp_stderr tmp_curl
	tmp_stdout="$OC_TMPDIR/stdout"
	tmp_stderr="$OC_TMPDIR/stderr"
	tmp_curl="$OC_TMPDIR/curl.args"
	: >"$tmp_curl"
	OC_STDOUT="$tmp_stdout"
	OC_STDERR="$tmp_stderr"
	OC_CURL_ARGS="$tmp_curl"
	export CURL_ARGS_FILE="$tmp_curl"
	HOME="$OC_HOME" PATH="$OC_BIN:$PATH" "$SCRIPT" oc "$@" >"$tmp_stdout" 2>"$tmp_stderr"
}

run_http_oc_expect_fail() {
	local tmp_stdout tmp_stderr tmp_curl
	tmp_stdout="$OC_TMPDIR/stdout"
	tmp_stderr="$OC_TMPDIR/stderr"
	tmp_curl="$OC_TMPDIR/curl.args"
	: >"$tmp_curl"
	OC_STDOUT="$tmp_stdout"
	OC_STDERR="$tmp_stderr"
	OC_CURL_ARGS="$tmp_curl"
	export CURL_ARGS_FILE="$tmp_curl"
	OC_EXIT=0
	HOME="$OC_HOME" PATH="$OC_BIN:$PATH" "$SCRIPT" oc "$@" >"$tmp_stdout" 2>"$tmp_stderr" || OC_EXIT=$?
}

write_basic_collection() {
	mkdir -p "$OC_ROOT/collectionA/requests"
	cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  environments:
    - name: development
      variables:
        - name: baseUrl
          value: https://dev.example.com
        - name: customerId
          value: env-customer
variables:
  - name: defaultHeader
    value: from-collection
YAML
	cat >"$OC_ROOT/collectionA/requests/get-smart-conditions.yaml" <<'YAML'
type: http
name: Get Smart Conditions
request:
  method: GET
  url: "{{baseUrl}}/smart-conditions/{{customerId}}"
  headers:
    - name: Accept
      value: application/json
    - name: X-Default
      value: "{{defaultHeader}}"
YAML
}

# ---------- Test 1: oc parser is available ----------
echo "test 1: oc parser is available"
setup_oc_tmp
write_basic_collection
run_http_oc --no-interactive -c collectionA -e development -n get-smart-conditions
assert_contains "$OC_STDOUT" "https://dev.example.com/smart-conditions/env-customer" "oc dry-run should build URL"
assert_contains "$OC_STDOUT" "Accept: application/json" "oc dry-run should include request header"
assert_not_contains "$OC_CURL_ARGS" "https://dev.example.com" "dry-run should not execute curl"

# ---------- Test 2: missing .httprc is a clear error ----------
echo "test 2: missing .httprc is a clear error"
setup_oc_tmp
rm -f "$OC_HOME/.config/.httprc"
run_http_oc_expect_fail --no-interactive -c collectionA -n get-smart-conditions
[ "$OC_EXIT" -eq 2 ] || {
	echo "FAIL: expected exit 2" >&2
	exit 1
}
assert_contains "$OC_STDERR" "~/.config/.httprc" "missing rc should mention expected path"

# ---------- Test 3: collection falls back to directory name ----------
echo "test 3: collection fallback directory name"
setup_oc_tmp
mkdir -p "$OC_ROOT/fallbackCollection/requests"
cat >"$OC_ROOT/fallbackCollection/opencollection.yaml" <<'YAML'
config:
  environments:
    - name: development
      variables:
        - name: baseUrl
          value: https://fallback.example.com
YAML
cat >"$OC_ROOT/fallbackCollection/requests/ping.yaml" <<'YAML'
type: http
request:
  method: GET
  url: "{{baseUrl}}/ping"
YAML
run_http_oc --no-interactive -c fallbackCollection -e development -n ping
assert_contains "$OC_STDOUT" "https://fallback.example.com/ping" "directory name should identify collection"

echo "OK"
