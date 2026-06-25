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

# ---------- Test 1: basic oc dry-run builds curl args ----------
echo "test 1: basic oc dry-run builds curl args"
setup_oc_tmp
write_basic_collection
run_http_oc --no-interactive -c collectionA -e development -n get-smart-conditions
assert_contains "$OC_STDOUT" "https://dev.example.com/smart-conditions/env-customer" "environment variables should resolve in URL"
assert_contains "$OC_STDOUT" "Accept: application/json" "request headers should be included"
assert_contains "$OC_STDOUT" "X-Default: from-collection" "collection variables should resolve in headers"
assert_not_contains "$OC_STDERR" "Traceback" "oc happy path should not traceback"
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
assert_not_contains "$OC_STDERR" "Traceback" "missing rc should not traceback"

# ---------- Test 3: invalid .httprc top-level shape is a clear error ----------
echo "test 3: invalid .httprc top-level shape is a clear error"
setup_oc_tmp
cat >"$OC_HOME/.config/.httprc" <<'YAML'
- not-a-mapping
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -n get-smart-conditions
[ "$OC_EXIT" -eq 2 ] || {
	echo "FAIL: expected exit 2" >&2
	exit 1
}
assert_contains "$OC_STDERR" "must be a YAML mapping" "invalid rc shape should be rejected clearly"
assert_not_contains "$OC_STDERR" "Traceback" "invalid rc shape should not traceback"

# ---------- Test 4: invalid collection manifest top-level shape is a clear error ----------
echo "test 4: invalid collection manifest top-level shape is a clear error"
setup_oc_tmp
mkdir -p "$OC_ROOT/badCollection"
cat >"$OC_ROOT/badCollection/opencollection.yaml" <<'YAML'
- not-a-mapping
YAML
run_http_oc_expect_fail --no-interactive -c badCollection -n request-name
[ "$OC_EXIT" -eq 2 ] || {
	echo "FAIL: expected exit 2" >&2
	exit 1
}
assert_contains "$OC_STDERR" "must be a YAML mapping" "invalid collection manifest shape should be rejected clearly"
assert_contains "$OC_STDERR" "opencollection.yaml" "invalid collection manifest should mention the manifest path"
assert_not_contains "$OC_STDERR" "Traceback" "invalid collection manifest shape should not traceback"

# ---------- Test 5: collection falls back to directory name ----------
echo "test 5: collection fallback directory name"
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

# ---------- Test 6: cli vars override environment vars and comma-separated vars work ----------
echo "test 6: cli vars override environment"
setup_oc_tmp
write_basic_collection
run_http_oc --no-interactive -c collectionA -e development -v "customerId=cli-customer,defaultHeader=cli-header" -n get-smart-conditions
assert_contains "$OC_STDOUT" "https://dev.example.com/smart-conditions/cli-customer" "CLI customer should win"
assert_contains "$OC_STDOUT" "X-Default: cli-header" "CLI header var should win"

# ---------- Test 7: request name is required in non-interactive mode ----------
echo "test 7: request name required non-interactive"
setup_oc_tmp
write_basic_collection
run_http_oc_expect_fail --no-interactive -c collectionA -e development -n
[ "$OC_EXIT" -eq 2 ] || {
	echo "FAIL: expected exit 2" >&2
	exit 1
}
assert_contains "$OC_STDERR" "request name is required" "missing request should be clear"

# ---------- Test 8: unknown request lists available requests ----------
echo "test 8: unknown request lists available"
setup_oc_tmp
write_basic_collection
run_http_oc_expect_fail --no-interactive -c collectionA -e development -n nope
[ "$OC_EXIT" -eq 2 ] || {
	echo "FAIL: expected exit 2" >&2
	exit 1
}
assert_contains "$OC_STDERR" "request not found: nope" "unknown request error"
assert_contains "$OC_STDERR" "get-smart-conditions" "available request listed"

# ---------- Test 9: ambiguous request name is rejected non-interactive ----------
echo "test 9: ambiguous request name is rejected non-interactive"
setup_oc_tmp
write_basic_collection
mkdir -p "$OC_ROOT/collectionA/requests/duplicate"
cat >"$OC_ROOT/collectionA/requests/duplicate/get-smart-conditions.yaml" <<'YAML'
type: http
request:
  method: GET
  url: "{{baseUrl}}/duplicate-smart-conditions/{{customerId}}"
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -e development -n get-smart-conditions
[ "$OC_EXIT" -eq 2 ] || {
	echo "FAIL: expected exit 2" >&2
	exit 1
}
assert_contains "$OC_STDERR" "request name is ambiguous:" "ambiguous request should be clear"
assert_contains "$OC_STDERR" "requests/get-smart-conditions.yaml" "first ambiguous request path listed"
assert_contains "$OC_STDERR" "requests/duplicate/get-smart-conditions.yaml" "second ambiguous request path listed"

# ---------- Test 10: missing variable fails in non-interactive mode ----------
echo "test 10: missing variable non-interactive"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/needs-var.yaml" <<'YAML'
type: http
request:
  method: GET
  url: "https://api.example.com/{{missingValue}}"
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -n needs-var
[ "$OC_EXIT" -eq 2 ] || {
	echo "FAIL: expected exit 2" >&2
	exit 1
}
assert_contains "$OC_STDERR" "missing variables" "missing variable error"
assert_contains "$OC_STDERR" "missingValue" "missing variable name"

# ---------- Test 11: disabled placeholders do not block resolved requests ----------
echo "test 11: disabled placeholders are ignored"
setup_oc_tmp
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
YAML
cat >"$OC_ROOT/collectionA/requests/ignored-vars.yaml" <<'YAML'
type: http
request:
  method: GET
  url: "{{baseUrl}}/ok"
  headers:
    - name: X-Disabled
      value: "{{ignoredHeader}}"
      disabled: true
  params:
    - name: ignored
      value: "{{ignoredQuery}}"
      type: query
      disabled: true
YAML
run_http_oc --no-interactive -c collectionA -e development -n ignored-vars
assert_contains "$OC_STDOUT" "https://dev.example.com/ok" "used URL variables should still resolve"
assert_not_contains "$OC_STDERR" "missing variables" "disabled placeholders should not trigger missing-variable errors"

# ---------- Test 12: body disabled entries and CLI append ----------
echo "test 12: body disabled entries and CLI append"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
variables:
  - name: baseUrl
    value: https://api.example.com
  - name: customerId
    value: from-path-param
YAML
cat >"$OC_ROOT/collectionA/requests/create.yaml" <<'YAML'
type: http
request:
  method: POST
  url: "{{baseUrl}}/customers/{{customerId}}/items"
  headers:
    - name: X-Enabled
      value: "yes"
    - name: X-Customer
      value: "{{customerId}}"
    - name: X-Disabled
      value: "no"
      disabled: true
  params:
    - name: customerId
      value: path-customer
      type: path
    - name: enabled
      value: "1"
      type: query
    - name: disabled
      value: "1"
      type: query
      disabled: true
  body:
    type: json
    data: '{"name":"{{itemName}}"}'
YAML
run_http_oc --no-interactive -c collectionA -v itemName=book -H "X-CLI: yes" -q "cli=1" -n create
assert_contains "$OC_STDOUT" "-X POST" "POST should emit method"
assert_contains "$OC_STDOUT" "https://api.example.com/customers/path-customer/items?enabled=1&cli=1" "path/query params should resolve"
assert_contains "$OC_STDOUT" "X-Enabled: yes" "enabled header present"
assert_contains "$OC_STDOUT" "X-Customer: path-customer" "path-param-derived variables should resolve in other templated fields"
assert_contains "$OC_STDOUT" "X-CLI: yes" "CLI header appended"
assert_contains "$OC_STDOUT" "Content-Type: application/json" "json body content type"
assert_contains "$OC_STDOUT" "--data" "body data flag present"
assert_contains "$OC_STDOUT" '"name":"book"' "body variable resolved"
assert_not_contains "$OC_STDOUT" "X-Disabled" "disabled header ignored"
assert_not_contains "$OC_STDOUT" "disabled=1" "disabled query ignored"

# ---------- Test 13: explicit content type wins ----------
echo "test 13: explicit content type wins"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/text-body.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/text
  headers:
    - name: Content-Type
      value: application/custom
  body:
    type: text
    data: hello
YAML
run_http_oc --no-interactive -c collectionA -n text-body
assert_contains "$OC_STDOUT" "Content-Type: application/custom" "explicit content type present"
assert_not_contains "$OC_STDOUT" "Content-Type: text/plain" "default content type suppressed"

# ---------- Test 14: missing variables in path params and body fail early ----------
echo "test 14: missing variables in path params and body"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
variables:
  - name: baseUrl
    value: https://api.example.com
YAML
cat >"$OC_ROOT/collectionA/requests/missing-body-path.yaml" <<'YAML'
type: http
request:
  method: POST
  url: "{{baseUrl}}/customers/{{customerId}}"
  params:
    - name: customerId
      value: "{{missingPathValue}}"
      type: path
  body:
    type: json
    data: '{"name":"{{missingBodyValue}}"}'
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -n missing-body-path
[ "$OC_EXIT" -eq 2 ] || {
	echo "FAIL: expected exit 2" >&2
	exit 1
}
assert_contains "$OC_STDERR" "missing variables" "missing path/body variables should fail during preflight"
assert_contains "$OC_STDERR" "missingPathValue" "missing path variable should be reported"
assert_contains "$OC_STDERR" "missingBodyValue" "missing body variable should be reported"
assert_not_contains "$OC_STDERR" "customerId" "URL placeholder supplied by path params should not be reported missing"

# ---------- Test 15: xml and sparql body types map content type ----------
echo "test 15: xml and sparql body types map content type"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/xml-body.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/xml
  body:
    type: xml
    data: '<x/>'
YAML
cat >"$OC_ROOT/collectionA/requests/sparql-body.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/sparql
  body:
    type: sparql
    data: 'SELECT * WHERE { ?s ?p ?o }'
YAML
run_http_oc --no-interactive -c collectionA -n xml-body
assert_contains "$OC_STDOUT" "Content-Type: application/xml" "xml body should map to application/xml"
run_http_oc --no-interactive -c collectionA -n sparql-body
assert_contains "$OC_STDOUT" "Content-Type: application/sparql-query" "sparql body should map to application/sparql-query"

# ---------- Test 16: unsupported body type errors ----------
echo "test 16: unsupported body type"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/upload.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/upload
  body:
    type: multipart-form
    data: []
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -n upload
[ "$OC_EXIT" -eq 2 ] || { echo "FAIL: expected exit 2" >&2; exit 1; }
assert_contains "$OC_STDERR" "unsupported request.body type" "unsupported body error"

# ---------- Test 17: unsupported auth type errors ----------
echo "test 17: unsupported auth type"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
request:
  auth:
    type: basic
YAML
cat >"$OC_ROOT/collectionA/requests/ping.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/ping
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -n ping
[ "$OC_EXIT" -eq 2 ] || { echo "FAIL: expected exit 2" >&2; exit 1; }
assert_contains "$OC_STDERR" "unsupported auth type for MVP: basic" "unsupported auth error"

# ---------- Test 18: request auth overrides collection auth ----------
echo "test 18: request auth overrides collection auth"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
request:
  auth:
    type: basic
YAML
cat >"$OC_ROOT/collectionA/requests/override-auth.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/override-auth
  auth:
    type: oauth2
    grantType: client_credentials
YAML
run_http_oc --no-interactive -c collectionA -n override-auth
assert_contains "$OC_STDOUT" "https://api.example.com/override-auth" "request-level supported auth should override collection-level unsupported auth"
assert_not_contains "$OC_STDERR" "unsupported auth type for MVP: basic" "collection-level auth should not win over request auth"

# ---------- Test 19: oauth2 client credentials adds bearer token ----------
echo "test 19: oauth2 client credentials"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
variables:
  - name: tokenUrl
    value: https://auth.example.com/token
  - name: clientId
    value: my-client
  - name: clientSecret
    value: my secret&secret
  - name: scope
    value: scope one/two
request:
  auth:
    type: oauth2
    grantType: client_credentials
    tokenUrl: "{{tokenUrl}}"
    clientId: "{{clientId}}"
    clientSecret: "{{clientSecret}}"
    scope: "{{scope}}"
YAML
cat >"$OC_ROOT/collectionA/requests/secure.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/secure
YAML
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_STDOUT" "Authorization: Bearer stub-token" "bearer token from oauth stub"
assert_contains "$OC_CURL_ARGS" "https://auth.example.com/token" "token endpoint should be called"
assert_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "client_credentials grant should be requested"
assert_contains "$OC_CURL_ARGS" "client_id=my-client" "client id should be form-encoded"
assert_contains "$OC_CURL_ARGS" "client_secret=my+secret%26secret" "client secret should be form-encoded"
assert_contains "$OC_CURL_ARGS" "scope=scope+one%2Ftwo" "scope should be form-encoded"
cache_file="$(find "$OC_HOME/.cache/http-oc" -type f | head -1)"
[ -n "$cache_file" ] || { echo "FAIL: expected cache file" >&2; exit 1; }
cache_mode="$(stat -f %Lp "$cache_file")"
[ "$cache_mode" = "600" ] || { echo "FAIL: expected cache mode 600, got $cache_mode" >&2; exit 1; }

# ---------- Test 20: oauth2 token cache is reused ----------
echo "test 20: oauth2 cache reused"
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_STDOUT" "Authorization: Bearer stub-token" "cached bearer token reused"
assert_not_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "cache reuse should avoid a second token request"

# ---------- Test 21: malformed oauth2 cache is treated as a miss ----------
echo "test 21: malformed oauth2 cache is treated as a miss"
printf '{"access_token":"cached-token","expires_at":"not-a-number"}\n' >"$cache_file"
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_STDOUT" "Authorization: Bearer stub-token" "malformed cache should fall back to a fresh token"
assert_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "malformed cache should trigger a new token request"

echo "OK"
