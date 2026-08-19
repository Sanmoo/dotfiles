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
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: expected exit 2" >&2
  exit 1
}
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
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: expected exit 2" >&2
  exit 1
}
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
assert_contains "$OC_STDOUT" "Authorization: Bearer ***" "bearer token from oauth stub"
assert_contains "$OC_STDOUT" "'Authorization: Bearer ***'" "closing quote should be preserved on masked bearer header"
assert_contains "$OC_CURL_ARGS" "https://auth.example.com/token" "token endpoint should be called"
assert_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "client_credentials grant should be requested"
assert_contains "$OC_CURL_ARGS" "client_id=my-client" "client id should be form-encoded"
assert_contains "$OC_CURL_ARGS" "client_secret=my+secret%26secret" "client secret should be form-encoded"
assert_contains "$OC_CURL_ARGS" "scope=scope+one%2Ftwo" "scope should be form-encoded"
cache_file="$(find "$OC_HOME/.cache/http-oc" -type f | head -1)"
[ -n "$cache_file" ] || {
  echo "FAIL: expected cache file" >&2
  exit 1
}
if stat -c '%a' "$cache_file" >/dev/null 2>&1; then
  cache_mode="$(stat -c '%a' "$cache_file")"
else
  cache_mode="$(stat -f %Lp "$cache_file")"
fi
[ "$cache_mode" = "600" ] || {
  echo "FAIL: expected cache mode 600, got $cache_mode" >&2
  exit 1
}

# ---------- Test 20: oauth2 token cache is reused ----------
echo "test 20: oauth2 cache reused"
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_STDOUT" "Authorization: Bearer ***" "cached bearer token reused"
assert_not_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "cache reuse should avoid a second token request"

# ---------- Test 21: malformed oauth2 cache is treated as a miss ----------
echo "test 21: malformed oauth2 cache is treated as a miss"
printf '{"access_token":"cached-token","expires_at":"not-a-number"}\n' >"$cache_file"
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_STDOUT" "Authorization: Bearer ***" "malformed cache should fall back to a fresh token"
assert_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "malformed cache should trigger a new token request"

# ---------- Test 22: oauth2 authorization code calls helper and adds bearer ----------
echo "test 22: oauth2 authorization code"
setup_oc_tmp
cat >"$OC_BIN/auth-code-token" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$AUTH_CODE_ARGS_FILE"
printf '{"access_token":"auth-code-token","token_type":"Bearer","expires_in":3600}\n'
STUB
chmod +x "$OC_BIN/auth-code-token"
export AUTH_CODE_ARGS_FILE="$OC_TMPDIR/auth-code.args"
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
request:
  auth:
    type: oauth2
    grantType: authorization_code
    authorizationUrl: https://auth.example.com/authorize
    tokenUrl: https://auth.example.com/token
    clientId: browser-client
    scope: openid profile
    redirectUri: http://127.0.0.1:8765/callback
YAML
cat >"$OC_ROOT/collectionA/requests/browser.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/browser
YAML
run_http_oc --no-interactive -c collectionA -n browser
assert_contains "$OC_STDOUT" "Authorization: Bearer ***" "auth code bearer token"
assert_contains "$OC_STDOUT" "'Authorization: Bearer ***'" "closing quote should be preserved on masked bearer header (auth code)"
assert_contains "$AUTH_CODE_ARGS_FILE" "browser-client" "helper gets client id"
assert_contains "$AUTH_CODE_ARGS_FILE" "https://auth.example.com/authorize" "helper gets auth url"
assert_contains "$AUTH_CODE_ARGS_FILE" "https://auth.example.com/token" "helper gets token url"
assert_not_contains "$AUTH_CODE_ARGS_FILE" "--force-login" "default call should not force login"
run_http_oc --no-interactive -c collectionA --auth-no-cache -n browser
assert_contains "$OC_STDOUT" "Authorization: Bearer ***" "auth code bearer token with auth-no-cache"
assert_contains "$AUTH_CODE_ARGS_FILE" "--force-login" "auth-no-cache should pass --force-login to helper"

# ---------- Test 23: interactive fzf can choose collection and request ----------
echo "test 23: fzf selection"
setup_oc_tmp
write_basic_collection
cat >"$OC_BIN/fzf" <<'STUB'
#!/usr/bin/env bash
IFS= read -r first
printf '%s\n' "$first"
STUB
chmod +x "$OC_BIN/fzf"
if command -v script >/dev/null 2>&1; then
  set +e
  if script -qec "exit 0" /dev/null >/dev/null 2>&1; then
    HOME="$OC_HOME" PATH="$OC_BIN:$PATH" CURL_ARGS_FILE="$OC_TMPDIR/curl.args" script -qec "$SCRIPT oc -e development -n" /dev/null >"$OC_TMPDIR/script.out" 2>"$OC_TMPDIR/script.err"
  else
    HOME="$OC_HOME" PATH="$OC_BIN:$PATH" CURL_ARGS_FILE="$OC_TMPDIR/curl.args" script -q /dev/null "$SCRIPT" oc -e development -n >"$OC_TMPDIR/script.out" 2>"$OC_TMPDIR/script.err"
  fi
  status=$?
  set -e
  [ "$status" -eq 0 ] || {
    echo "FAIL: interactive fzf command failed" >&2
    cat "$OC_TMPDIR/script.err" >&2
    exit 1
  }
  assert_contains "$OC_TMPDIR/script.out" "Collection: collectionA" "summary should show collection"
  assert_contains "$OC_TMPDIR/script.out" "Request: get-smart-conditions" "summary should show request"
  assert_contains "$OC_TMPDIR/script.out" "https://dev.example.com/smart-conditions/env-customer" "dry run URL"
  assert_contains "$OC_TMPDIR/script.out" "Comando equivalente: http oc -c collectionA -e development get-smart-conditions" "summary should show equivalent command"
else
  echo "skip: script command not available"
fi

# ---------- Test 24: equivalent command is printed even on failure ----------
echo "test 24: equivalent command on failure"
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
request:
  auth:
    type: basic
YAML
cat >"$OC_ROOT/collectionA/requests/ping.yaml" <<'YAML'
type: http
request:
  method: GET
  url: "{{baseUrl}}/ping"
YAML
cat >"$OC_BIN/fzf" <<'STUB'
#!/usr/bin/env bash
IFS= read -r first
printf '%s\n' "$first"
STUB
chmod +x "$OC_BIN/fzf"
if command -v script >/dev/null 2>&1; then
  set +e
  if script -qec "exit 0" /dev/null >/dev/null 2>&1; then
    HOME="$OC_HOME" PATH="$OC_BIN:$PATH" script -qec "$SCRIPT oc -e development -n" /dev/null >"$OC_TMPDIR/script.out" 2>"$OC_TMPDIR/script.err"
  else
    HOME="$OC_HOME" PATH="$OC_BIN:$PATH" script -q /dev/null "$SCRIPT" oc -e development -n >"$OC_TMPDIR/script.out" 2>"$OC_TMPDIR/script.err"
  fi
  status=$?
  set -e
  assert_contains "$OC_TMPDIR/script.out" "Comando equivalente: http oc -c collectionA -e development ping" "equivalent command should appear even when auth fails"
  [ "$status" -ne 0 ] || {
    echo "FAIL: expected non-zero exit" >&2
    exit 1
  }
else
  echo "skip: script command not available"
fi

# ---------- Test 25: --auth-no-cache forces fresh token ----------
echo "test 25: auth-no-cache forces fresh token"
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
    value: my-secret
request:
  auth:
    type: oauth2
    grantType: client_credentials
    tokenUrl: "{{tokenUrl}}"
    clientId: "{{clientId}}"
    clientSecret: "{{clientSecret}}"
YAML
cat >"$OC_ROOT/collectionA/requests/secure.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/secure
YAML
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_STDOUT" "Authorization: Bearer ***" "first call should get token"
assert_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "first call should request token"
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_STDOUT" "Authorization: Bearer ***" "second call from cache"
assert_not_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "second call should use cache"
run_http_oc --no-interactive -c collectionA --auth-no-cache -n secure
assert_contains "$OC_STDOUT" "Authorization: Bearer ***" "auth-no-cache should get token"
assert_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "auth-no-cache should force a new token request"

# ---------- Test 26: -v flag appears in equivalent command ----------
echo "test 26: -v in equivalent command"
setup_oc_tmp
write_basic_collection
cat >"$OC_BIN/fzf" <<'STUB'
#!/usr/bin/env bash
IFS= read -r first
printf '%s\n' "$first"
STUB
chmod +x "$OC_BIN/fzf"
if command -v script >/dev/null 2>&1; then
  set +e
  if script -qec "exit 0" /dev/null >/dev/null 2>&1; then
    HOME="$OC_HOME" PATH="$OC_BIN:$PATH" CURL_ARGS_FILE="$OC_TMPDIR/curl.args" script -qec "$SCRIPT oc -e development -n -v customerId=cli-override" /dev/null >"$OC_TMPDIR/script.out" 2>"$OC_TMPDIR/script.err"
  else
    HOME="$OC_HOME" PATH="$OC_BIN:$PATH" CURL_ARGS_FILE="$OC_TMPDIR/curl.args" script -q /dev/null "$SCRIPT" oc -e development -n -v "customerId=cli-override" >"$OC_TMPDIR/script.out" 2>"$OC_TMPDIR/script.err"
  fi
  status=$?
  set -e
  [ "$status" -eq 0 ] || {
    echo "FAIL: interactive fzf command with -v failed" >&2
    cat "$OC_TMPDIR/script.err" >&2
    exit 1
  }
  assert_contains "$OC_TMPDIR/script.out" "Comando equivalente: http oc -c collectionA -e development -v customerId=cli-override get-smart-conditions" "equivalent command should include -v"
else
  echo "skip: script command not available"
fi

# ---------- Test 27: interactively prompted variable appears in equivalent command ----------
echo "test 27: prompted variable in equivalent command"
python3 <<'PYEOF'
import importlib.machinery, sys, builtins, os
loader = importlib.machinery.SourceFileLoader('http', 'general/bin/http')
http = loader.load_module()
collection_manifest = {
    "info": {"name": "test-collection"},
    "config": {"environments": []},
}
request_data = {
    "request": {"method": "GET", "url": "https://api.example.com/{{apiToken}}"},
}
environment = {"name": "development"}
cli_vars = {"x": "1"}
original_input = builtins.input
responses = iter(["my-token-123"])
def fake_input(prompt=""):
    try:
        val = next(responses)
        return val
    except StopIteration:
        return original_input(prompt)
builtins.input = fake_input
try:
    variables, prompted, disabled_indexes = http.resolve_oc_variables(
        collection={"manifest": collection_manifest},
        request={"data": request_data},
        environment=environment,
        cli_vars=cli_vars,
        interactive=True,
    )
finally:
    builtins.input = original_input
assert "apiToken" in prompted, "prompted should contain apiToken"
assert prompted["apiToken"] == "my-token-123", f"expected my-token-123, got {prompted['apiToken']}"
effective = dict(cli_vars)
effective.update(prompted)
cmd = http.build_equivalent_command("test-collection", "development", "my-request", effective)
assert "-v" in cmd, f"equivalent command should include -v: {cmd}"
assert "x=1" in cmd, f"equivalent command should include cli var: {cmd}"
assert "apiToken=my-token-123" in cmd, f"equivalent command should include prompted var: {cmd}"
print("OK")
PYEOF

# ---------- Test 28: dqwnp parser and validation ----------
echo "test 28: dqwnp parser and validation"
python3 <<'PYEOF'
import importlib.machinery
import builtins

http = importlib.machinery.SourceFileLoader("http", "general/bin/http").load_module()

args = http.parse_args(["oc", "get-users", "--dqwnp"])
assert args.disable_queries_when_not_provided == [http.OC_ALL_QUERIES_SENTINEL]
assert args.request_name == "get-users"
assert http.parse_optional_query_selection(args.disable_queries_when_not_provided) == (True, set())

args = http.parse_args(["oc", "--dqwnp", "get-users"])
assert args.disable_queries_when_not_provided == [http.OC_ALL_QUERIES_SENTINEL]
assert args.request_name == "get-users"

args = http.parse_args([
    "oc", "get-users", "--dqwnp=page,limit",
    "--disable-query-when-not-provided=filter",
])
assert http.parse_optional_query_selection(args.disable_queries_when_not_provided) == (
    True, {"page", "limit", "filter"},
)

# ---------- Tests 29-32: optional query resolution ----------
request_doc = {"request": {"url": "https://example/{{shared}}", "params": [
    {"name": "filter", "type": "query", "value": "{{status}}/{{owner}}"},
    {"name": "filter", "type": "query", "value": "mirror={{status}}"},
    {"name": "format", "type": "query", "value": "json"},
]}}
vars_out, prompted, disabled = http.resolve_optional_queries(
    request_doc, {"status": ""}, {}, True, {"filter"}, False,
)
assert disabled == {0, 1}, "empty shared query variables disable duplicate covered queries"
assert http.optional_query_is_covered(request_doc["request"]["params"][2], True, {"format"})
assert not http.optional_query_is_covered(request_doc["request"]["params"][2], False, set())
assert "shared" in http.collect_missing_variables(request_doc, {}, disabled), \
"omitted query must not hide shared URL requirements"

# Real construction: a non-dict entry must not shift disabled indexes.
request_doc = {"request": {"url": "https://example.test", "params": [
"not-a-param", {"name": "page", "type": "query", "value": "{{page}}"},
{"name": "format", "type": "query", "value": "json"},
]}}
variables, _, disabled = http.resolve_oc_variables(
{"manifest": {"variables": []}}, {"data": request_doc}, None,
{"page": ""}, False, True, set(),
)
args = type("Args", (), {"headers": [], "queries": [], "data": None,
                          "include": False, "dry_run": True, "insecure": False,
                          "follow": False})()
direct = http.build_basic_oc_args(args, request_doc, variables, disabled)
assert direct.queries == ["format=json"], f"index mapping failed: {direct.queries}"

# An explicit empty CLI value disables the optional query but remains missing when required.
request_doc = {"request": {"url": "https://example.test/{{shared}}", "params": [
{"name": "optional", "type": "query", "value": "{{shared}}"},
]}}
try:
    http.resolve_oc_variables(
        {"manifest": {"variables": []}}, {"data": request_doc}, None,
        {"shared": ""}, False, True, set(),
    )
except SystemExit as error:
    assert error.code == 2, "shared empty CLI value must remain required"
else:
    raise AssertionError("empty shared CLI value incorrectly satisfied URL")

# Optional prompts must be merged with ordinary required prompts.
request_doc = {"request": {"url": "https://example.test/{{required}}", "params": [
{"name": "optional", "type": "query", "value": "{{optional}}"},
]}}
responses = iter(["optional-value", "required-value"])
original_input = builtins.input
builtins.input = lambda prompt="": next(responses)
try:
    variables, prompted, disabled = http.resolve_oc_variables(
        {"manifest": {"variables": []}}, {"data": request_doc}, None,
        {}, True, True, set(),
    )
finally:
    builtins.input = original_input
assert prompted == {"optional": "optional-value", "required": "required-value"}, prompted
assert disabled == set() and variables["optional"] == "optional-value"

request_doc = {"request": {"params": [
    {"name": "page", "type": "query", "value": "{{pageNumber}}"},
    {"name": "customerId", "type": "path", "value": "{{customerId}}"},
]}}
http.validate_optional_query_selection(request_doc, True, {"page"})

try:
    http.validate_optional_query_selection(request_doc, True, {"pages"})
except SystemExit as error:
    assert error.code == 2
else:
    raise AssertionError("unknown query should fail")

try:
    http.validate_optional_query_selection(request_doc, True, {"customerId"})
except SystemExit as error:
    assert error.code == 2
else:
    raise AssertionError("path parameter should fail")
PYEOF

# ---------- Test 29: dqwnp omits uncovered values non-interactively ----------
echo "test 29: dqwnp non-interactive omission"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
variables:
  - name: inheritedPage
    value: "99"
YAML
cat >"$OC_ROOT/collectionA/requests/search.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/search
  params:
    - name: page
      type: query
      value: "{{inheritedPage}}"
    - name: limit
      type: query
      value: "{{limit}}"
    - name: format
      type: query
      value: json
YAML
run_http_oc --no-interactive -c collectionA -n --dqwnp -v limit=20 search
assert_contains "$OC_STDOUT" "?limit=20&format=json" "explicit and literal queries should remain"
assert_not_contains "$OC_STDOUT" "page=99" "inherited values must not enable optional queries"

# ---------- Test 30: named dqwnp preserves unselected requirements ----------
echo "test 30: named dqwnp selection"
run_http_oc_expect_fail --no-interactive -c collectionA -n --dqwnp=page search
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: expected exit 2" >&2
  exit 1
}
assert_contains "$OC_STDERR" "limit" "unselected query variable should remain required"

# ---------- Test 31: explicit empty and multiple variables disable query ----------
echo "test 31: empty and multi-variable query omission"
cat >"$OC_ROOT/collectionA/requests/filter.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/filter
  params:
    - name: filter
      type: query
      value: "status:{{status}},owner:{{owner}}"
    - name: filter
      type: query
      value: "mirror:{{status}}"
YAML
run_http_oc --no-interactive -c collectionA -n --dqwnp=filter -v status= filter
assert_not_contains "$OC_STDOUT" "filter=" "empty value should omit every duplicate named query"

# ---------- Test 32: interactive dqwnp main_oc flow ----------
echo "test 32: interactive dqwnp main_oc flow"
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
    - name: staging
      variables:
        - name: baseUrl
          value: https://staging.example.com
YAML
cat >"$OC_ROOT/collectionA/requests/search.yaml" <<'YAML'
type: http
name: Search
request:
  method: GET
  url: "{{baseUrl}}/search"
  params:
    - name: page
      type: query
      value: "{{pageNumber}}"
YAML
cat >"$OC_BIN/fzf" <<'STUB'
#!/usr/bin/env bash
IFS= read -r first
printf '%s\n' "$first"
STUB
chmod +x "$OC_BIN/fzf"
if command -v script >/dev/null 2>&1; then
  set +e
  if script -qec "exit 0" /dev/null >/dev/null 2>&1; then
    {
      printf 'y\n\n'
      sleep 1
    } | HOME="$OC_HOME" PATH="$OC_BIN:$PATH" CURL_ARGS_FILE="$OC_TMPDIR/curl.args" script -qec "$SCRIPT oc -n" /dev/null >"$OC_TMPDIR/script.out" 2>"$OC_TMPDIR/script.err"
  else
    {
      printf 'y\n\n'
      sleep 1
    } | HOME="$OC_HOME" PATH="$OC_BIN:$PATH" CURL_ARGS_FILE="$OC_TMPDIR/curl.args" script -q /dev/null "$SCRIPT" oc -n >"$OC_TMPDIR/script.out" 2>"$OC_TMPDIR/script.err"
  fi
  status=$?
  set -e
  [ "$status" -eq 0 ] || {
    cat "$OC_TMPDIR/script.err" >&2
    exit 1
  }
  assert_contains "$OC_TMPDIR/script.out" "Allow disabling query parameters with an empty value? [y/N]" "activation prompt should be shown"
  assert_contains "$OC_TMPDIR/script.out" "value for pageNumber (leave empty to disable)" "optional value prompt should be shown"
  assert_contains "$OC_TMPDIR/script.out" "Comando equivalente: http oc -c collectionA -e development --dqwnp search" "equivalent command should thread optional selection"
  assert_contains "$OC_TMPDIR/script.out" "https://dev.example.com/search" "selected environment should be used"
  assert_not_contains "$OC_TMPDIR/script.out" "page=" "empty optional query should be omitted"
else
  echo "skip: script command not available"
fi

# ---------- Test 33: interactive dqwnp activation and empty omission ----------
echo "test 33: interactive dqwnp activation"
python3 <<'PYEOF'
import builtins
import importlib.machinery

http = importlib.machinery.SourceFileLoader("http", "general/bin/http").load_module()
responses = iter(["y", ""])
prompts = []
def fake_input(prompt=""):
    prompts.append(prompt)
    return next(responses)

request_doc = {"request": {
    "method": "GET",
    "url": "https://api.example.com/search",
    "params": [{"name": "page", "type": "query", "value": "{{pageNumber}}"}],
}}
original_input = builtins.input
builtins.input = fake_input
try:
    enabled = http.prompt_enable_optional_queries()
    variables, prompted, disabled = http.resolve_optional_queries(
        request_doc, {}, {}, enabled, set(), True,
    )
finally:
    builtins.input = original_input
assert enabled is True
assert disabled == {0}
assert prompts == [
    "Allow disabling query parameters with an empty value? [y/N] ",
    "value for pageNumber (leave empty to disable): ",
]
assert prompted == {"pageNumber": ""}
cmd = http.build_equivalent_command("collectionA", "development", "search", {}, True, set())
assert "--dqwnp" in cmd
responses = iter([""])
builtins.input = lambda prompt="": next(responses)
try:
    assert http.prompt_enable_optional_queries() is False
finally:
    builtins.input = original_input
named_cmd = http.build_equivalent_command(
    "collectionA", "", "search", {}, True, {"limit", "page"},
)
assert "--dqwnp=limit,page" in named_cmd
PYEOF

# ---------- Test 34: form-urlencoded body follows OpenCollection schema ----------
echo "test 34: form-urlencoded body"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
variables:
  - name: username
    value: alice
  - name: password
    value: "p@ss word&more"
YAML
cat >"$OC_ROOT/collectionA/requests/login.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/login
  body:
    type: form-urlencoded
    data:
      - name: username
        value: "{{username}}"
      - name: password
        value: "{{password}}"
      - name: remember
        value: "true"
        disabled: true
YAML
run_http_oc --no-interactive -c collectionA -n login
assert_contains "$OC_STDOUT" "Content-Type: application/x-www-form-urlencoded" "form body content type"
assert_contains "$OC_STDOUT" "--data 'username=alice&password=p%40ss+word%26more'" "form fields should be URL-encoded"
assert_not_contains "$OC_STDOUT" "remember=true" "disabled form field ignored"

# ---------- Test 35: malformed form-urlencoded data is rejected ----------
echo "test 35: malformed form-urlencoded body"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/invalid-form.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/login
  body:
    type: form-urlencoded
    data:
      - name: username
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -n invalid-form
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: expected exit 2" >&2
  exit 1
}
assert_contains "$OC_STDERR" "form-urlencoded body data" "malformed form body error"

# ---------- Test 36: explicit form Content-Type wins ----------
echo "test 36: explicit form content type wins"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/explicit-form.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/login
  headers:
    - name: Content-Type
      value: application/custom-form
  body:
    type: form-urlencoded
    data:
      - name: key
        value: value
YAML
run_http_oc --no-interactive -c collectionA -n explicit-form
assert_contains "$OC_STDOUT" "Content-Type: application/custom-form" "explicit content type present"
assert_not_contains "$OC_STDOUT" "Content-Type: application/x-www-form-urlencoded" "default content type suppressed"

# ---------- Test 37: -d overrides manifest body ----------
echo "test 37: -d overrides manifest body"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
variables:
  - name: baseUrl
    value: https://api.example.com
YAML
cat >"$OC_ROOT/collectionA/requests/create.yaml" <<'YAML'
type: http
request:
  method: POST
  url: "{{baseUrl}}/items"
  body:
    type: json
    data: '{"name":"from-manifest"}'
YAML
run_http_oc --no-interactive -c collectionA -n -d '{"name":"from-cli"}' create
assert_contains "$OC_STDOUT" "--data '{\"name\":\"from-cli\"}'" "cli body should win"
assert_contains "$OC_STDOUT" "Content-Type: application/json" "json content type inherited"
assert_not_contains "$OC_STDOUT" "from-manifest" "manifest body should be replaced"

# ---------- Test 38: -f overrides manifest body ----------
echo "test 38: -f overrides manifest body"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/create.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/items
  body:
    type: json
    data: '{"name":"from-manifest"}'
YAML
PAYLOAD="$OC_TMPDIR/payload.json"
echo '{"name":"from-file"}' >"$PAYLOAD"
run_http_oc --no-interactive -c collectionA -n -f "$PAYLOAD" create
assert_contains "$OC_STDOUT" "--data @$PAYLOAD" "file body should be sent via --data @file"
assert_contains "$OC_STDOUT" "Content-Type: application/json" "json content type from extension"
assert_not_contains "$OC_STDOUT" "from-manifest" "manifest body should be replaced"

# ---------- Test 39: -d and -f together is an error ----------
echo "test 39: -d and -f together is an error"
setup_oc_tmp
write_basic_collection
run_http_oc_expect_fail --no-interactive -c collectionA -n -d x -f "$OC_TMPDIR/nope.json" get-smart-conditions
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: expected exit 2" >&2
  exit 1
}
assert_contains "$OC_STDERR" "mutually exclusive" "exclusive error"

# ---------- Test 40: -f with missing file is an error ----------
echo "test 40: -f with missing file is an error"
setup_oc_tmp
write_basic_collection
run_http_oc_expect_fail --no-interactive -c collectionA -n -f /tmp/does-not-exist-12345.json get-smart-conditions
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: expected exit 2" >&2
  exit 1
}
assert_contains "$OC_STDERR" "file not found" "missing file error"

# ---------- Test 41: -d inherits manifest body content type ----------
echo "test 41: -d inherits manifest body content type"
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
    data: '<orig/>'
YAML
run_http_oc --no-interactive -c collectionA -n -d '<cli/>' xml-body
assert_contains "$OC_STDOUT" "Content-Type: application/xml" "manifest xml type inherited"
assert_contains "$OC_STDOUT" "--data '<cli/>'" "cli body sent"

# ---------- Test 42: -f extension wins over manifest body type ----------
echo "test 42: -f extension wins over manifest body type"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/create.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/items
  body:
    type: json
    data: '{}'
YAML
PAYLOAD="$OC_TMPDIR/payload.xml"
echo '<cli/>' >"$PAYLOAD"
run_http_oc --no-interactive -c collectionA -n -f "$PAYLOAD" create
assert_contains "$OC_STDOUT" "Content-Type: application/xml" "file extension should win"
assert_not_contains "$OC_STDOUT" "Content-Type: application/json" "manifest json type should not apply"

# ---------- Test 43: -d defaults to application/json without manifest body ----------
echo "test 43: -d defaults to application/json without manifest body"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/ping.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/ping
YAML
run_http_oc --no-interactive -c collectionA -n -d '{"x":1}' ping
assert_contains "$OC_STDOUT" "Content-Type: application/json" "json default content type"
assert_contains "$OC_STDOUT" "--data '{\"x\":1}'" "cli body sent"

# ---------- Test 44: explicit -H Content-Type wins over override defaults ----------
echo "test 44: explicit -H Content-Type wins over override defaults"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/ping.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/ping
YAML
run_http_oc --no-interactive -c collectionA -n -d '{"x":1}' -H "Content-Type: application/custom" ping
assert_contains "$OC_STDOUT" "Content-Type: application/custom" "explicit content type wins"
assert_not_contains "$OC_STDOUT" "Content-Type: application/json" "json default suppressed"

# ---------- Test 45: -d on form-urlencoded request is sent verbatim ----------
echo "test 45: -d on form-urlencoded request is sent verbatim"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/login.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/login
  body:
    type: form-urlencoded
    data:
      - name: username
        value: alice
YAML
run_http_oc --no-interactive -c collectionA -n -d 'a=1&b=x%20y' login
assert_contains "$OC_STDOUT" "--data 'a=1&b=x%20y'" "cli form body verbatim"
assert_contains "$OC_STDOUT" "Content-Type: application/x-www-form-urlencoded" "form content type inherited"
assert_not_contains "$OC_STDOUT" "username=alice" "manifest form fields replaced"

# ---------- Test 46: -f .jsonc comments stripped ----------
echo "test 46: -f .jsonc comments stripped"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/create.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/items
YAML
PAYLOAD="$OC_TMPDIR/payload.jsonc"
cat >"$PAYLOAD" <<'JSONC'
// comment
{"name":"alice"}
JSONC
run_http_oc --no-interactive -c collectionA -n -f "$PAYLOAD" create
assert_contains "$OC_STDOUT" '"name":"alice"' "jsonc body content present"
assert_not_contains "$OC_STDOUT" "comment" "jsonc comment stripped"

# ---------- Test 47: -v substitutes in -d ----------
echo "test 47: -v substitutes in -d"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/create.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/items
YAML
run_http_oc --no-interactive -c collectionA -n -v "name=alice" -d '{"name":"{{name}}"}' create
assert_contains "$OC_STDOUT" '"name":"alice"' "cli body variable resolved"

# ---------- Test 48: undefined variable in -d is an error ----------
echo "test 48: undefined variable in -d is an error"
setup_oc_tmp
write_basic_collection
run_http_oc_expect_fail --no-interactive -c collectionA -n -d '{"name":"{{NOPE}}"' get-smart-conditions
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: expected exit 2" >&2
  exit 1
}
assert_contains "$OC_STDERR" "missing variables" "missing variable error"
assert_contains "$OC_STDERR" "NOPE" "missing variable name"

# ---------- Test 49: manifest body variables exempt when overridden ----------
echo "test 49: manifest body variables exempt when overridden"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/create.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/items
  body:
    type: json
    data: '{"name":"{{missingBodyValue}}"}'
YAML
run_http_oc --no-interactive -c collectionA -n -d '{"name":"cli"}' create
assert_contains "$OC_STDOUT" "--data '{\"name\":\"cli\"}'" "override body sent"
assert_not_contains "$OC_STDERR" "missing variables" "manifest body vars should not be required"

# ---------- Test 50: -d with empty value sends empty body ----------
echo "test 50: -d with empty value sends empty body"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/ping.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/ping
YAML
run_http_oc --no-interactive -c collectionA -n -d "" ping
assert_contains "$OC_STDOUT" "--data ''" "empty body should emit --data with empty string"

# ---------- Test 51: -d appears in equivalent command ----------
echo "test 51: -d in equivalent command"
python3 <<'PYEOF'
import importlib.machinery

http = importlib.machinery.SourceFileLoader("http", "general/bin/http").load_module()
cmd = http.build_equivalent_command(
    "collectionA", "development", "create", {"x": "1"},
    False, set(), data='{"x":1}',
)
assert "-d '{\"x\":1}'" in cmd, cmd
cmd = http.build_equivalent_command(
    "collectionA", "development", "create", {}, False, set(), data="hello world",
)
assert "-d 'hello world'" in cmd, cmd
print("OK")
PYEOF

# ---------- Test 52: -f appears in equivalent command ----------
echo "test 52: -f in equivalent command"
python3 <<'PYEOF'
import importlib.machinery

http = importlib.machinery.SourceFileLoader("http", "general/bin/http").load_module()
cmd = http.build_equivalent_command(
    "collectionA", "development", "create", {}, False, set(), file="/tmp/payload.json",
)
assert "-f /tmp/payload.json" in cmd, cmd
print("OK")
PYEOF

# ---------- Test 53: -f contents are templated (incl. path params) ----------
echo "test 53: -f contents are templated (incl. path params)"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
cat >"$OC_ROOT/collectionA/requests/create.yaml" <<'YAML'
type: http
request:
  method: POST
  url: https://api.example.com/customers/{{customerId}}/items
  params:
    - name: customerId
      value: path-42
      type: path
YAML
PAYLOAD="$OC_TMPDIR/templated.json"
echo '{"name":"{{NAME}}","id":"{{customerId}}"}' >"$PAYLOAD"
run_http_oc --no-interactive -c collectionA -n -v "NAME=alice" -f "$PAYLOAD" create
assert_contains "$OC_STDOUT" '"name":"alice"' "file body cli variable resolved"
assert_contains "$OC_STDOUT" '"id":"path-42"' "path param resolved in file body"
assert_not_contains "$OC_STDOUT" '{{' "template placeholders all resolved"

# ---------- Test 54: manifest pem entry -> --cert/--key/--pass ----------
write_mtls_collection() {
  mkdir -p "$OC_ROOT/collectionA/requests" "$OC_ROOT/collectionA/certs"
  cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
  cat >"$OC_ROOT/collectionA/requests/get.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/secure
YAML
}

echo "test 54: manifest pem entry -> --cert/--key/--pass (executed + dry-run)"
setup_oc_tmp
write_mtls_collection
printf 'fake-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'fake-key\n' >"$OC_ROOT/collectionA/certs/client.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<YAML
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/client.pem
      privateKeyFilePath: certs/client.key
      passphrase: secret
YAML
run_http_oc --no-interactive -c collectionA get
assert_contains "$OC_CURL_ARGS" "--cert" "executed curl receives --cert"
assert_contains "$OC_CURL_ARGS" "$OC_ROOT/collectionA/certs/client.pem" "executed curl certificate path"
assert_contains "$OC_CURL_ARGS" "--key" "executed curl receives --key"
assert_contains "$OC_CURL_ARGS" "$OC_ROOT/collectionA/certs/client.key" "executed curl key path"
assert_contains "$OC_CURL_ARGS" "--pass" "executed curl receives --pass"
assert_contains "$OC_CURL_ARGS" "secret" "executed curl passphrase"
run_http_oc --no-interactive -c collectionA -n get
assert_contains "$OC_STDOUT" "--cert" "dry-run curl receives --cert"
assert_contains "$OC_STDOUT" "--key" "dry-run curl receives --key"
assert_contains "$OC_STDOUT" "--pass" "dry-run curl receives --pass"
assert_contains "$OC_STDOUT" "certs/client.pem" "dry-run shows certificate path"
assert_contains "$OC_STDOUT" "certs/client.key" "dry-run shows key path"

# ---------- Test 55: exact match only, prefix-sharing host excluded ----------
echo "test 55: exact domain match; prefix-sharing host excluded"
setup_oc_tmp
write_mtls_collection
printf 'fake-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'fake-key\n' >"$OC_ROOT/collectionA/certs/client.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/client.pem
      privateKeyFilePath: certs/client.key
YAML
cat >"$OC_ROOT/collectionA/requests/evil.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com.evil.com/secure
YAML
run_http_oc --no-interactive -c collectionA get
assert_contains "$OC_CURL_ARGS" "--cert" "exact-matching host gets the certificate"
run_http_oc --no-interactive -c collectionA -n evil
assert_not_contains "$OC_STDOUT" "--cert" "prefix-sharing host must not receive the certificate"

# ---------- Test 56: wildcard matches subdomains, not apex; http never matches ----------
echo "test 56: *.example.com subdomains only; http never matches"
setup_oc_tmp
write_mtls_collection
printf 'fake-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'fake-key\n' >"$OC_ROOT/collectionA/certs/client.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: "*.example.com"
      type: pem
      certificateFilePath: certs/client.pem
      privateKeyFilePath: certs/client.key
YAML
cat >"$OC_ROOT/collectionA/requests/sub.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://deep.api.example.com/secure
YAML
cat >"$OC_ROOT/collectionA/requests/apex.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.com/secure
YAML
cat >"$OC_ROOT/collectionA/requests/plain.yaml" <<'YAML'
type: http
request:
  method: GET
  url: http://api.example.com/secure
YAML
run_http_oc --no-interactive -c collectionA -n sub
assert_contains "$OC_STDOUT" "--cert" "wildcard matches a subdomain"
run_http_oc --no-interactive -c collectionA -n apex
assert_not_contains "$OC_STDOUT" "--cert" "wildcard must not match the apex domain"
run_http_oc --no-interactive -c collectionA -n plain
assert_not_contains "$OC_STDOUT" "--cert" "non-https URL must never match"

# ---------- Test 57: first match wins; disabled entries skipped ----------
echo "test 57: first match wins; disabled entries skipped"
setup_oc_tmp
write_mtls_collection
printf 'first-cert\n' >"$OC_ROOT/collectionA/certs/first.pem"
printf 'first-key\n' >"$OC_ROOT/collectionA/certs/first.key"
printf 'wild-cert\n' >"$OC_ROOT/collectionA/certs/wild.pem"
printf 'wild-key\n' >"$OC_ROOT/collectionA/certs/wild.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/first.pem
      privateKeyFilePath: certs/first.key
    - domain: "*.example.com"
      type: pem
      certificateFilePath: certs/wild.pem
      privateKeyFilePath: certs/wild.key
YAML
run_http_oc --no-interactive -c collectionA -n get
assert_contains "$OC_STDOUT" "certs/first.pem" "first matching entry should win"
assert_not_contains "$OC_STDOUT" "certs/wild.pem" "later matching entry must not be used"
# disabled entry referencing a missing file must be skipped, not an error
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/disabled.pem
      privateKeyFilePath: certs/disabled.key
      disabled: true
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/first.pem
      privateKeyFilePath: certs/first.key
YAML
run_http_oc --no-interactive -c collectionA get
assert_contains "$OC_CURL_ARGS" "certs/first.pem" "disabled entry skipped; enabled entry used"
assert_not_contains "$OC_CURL_ARGS" "certs/disabled.pem" "disabled entry file never referenced"

# ---------- Test 58: templating, ~/$VAR expansion, relative resolution ----------
echo "test 58: cert fields templated and paths resolved against collection root"
setup_oc_tmp
write_mtls_collection
printf 'fake-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'fake-key\n' >"$OC_ROOT/collectionA/certs/client.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
variables:
  - name: certDomain
    value: api.example.com
  - name: certFileName
    value: client.pem
config:
  clientCertificates:
    - domain: "{{certDomain}}"
      type: pem
      certificateFilePath: "certs/{{certFileName}}"
      privateKeyFilePath: "certs/client.key"
YAML
run_http_oc --no-interactive -c collectionA -n get
assert_contains "$OC_STDOUT" "certs/client.pem" "templated relative path resolves against collection root"
assert_contains "$OC_STDOUT" "certs/client.key" "relative key path resolves"
# {{process.env.X}} and ~ expansion in paths
mkdir -p "$OC_HOME/.mtls" "$OC_TMPDIR/certs"
printf 'env-cert\n' >"$OC_HOME/.mtls/client.pem"
printf 'env-key\n' >"$OC_TMPDIR/certs/client.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<YAML
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: "~/.mtls/client.pem"
      privateKeyFilePath: "{{process.env.MTLS_KEY_PATH}}"
YAML
MTLS_KEY_PATH="$OC_TMPDIR/certs/client.key" run_http_oc --no-interactive -c collectionA -n get
assert_contains "$OC_STDOUT" "client.pem" "tilde-expanded path resolves (process env branch)"
assert_contains "$OC_STDOUT" "$OC_TMPDIR/certs/client.key" "{{process.env.X}} path resolves"

# ---------- Test 59: missing required field exits 2 naming the field ----------
echo "test 59: missing required certificate field exits 2 naming the field"
for missing in type domain certificateFilePath privateKeyFilePath; do
  setup_oc_tmp
  write_mtls_collection
  {
    echo "info:"
    echo "  name: collectionA"
    echo "config:"
    echo "  clientCertificates:"
    if [ "$missing" = "domain" ]; then
      printf '    - type: pem\n'
    else
      printf '    - domain: api.example.com\n'
      if [ "$missing" != "type" ]; then
        printf '      type: pem\n'
      fi
    fi
    if [ "$missing" != "certificateFilePath" ]; then
      printf '      certificateFilePath: certs/client.pem\n'
    fi
    if [ "$missing" != "privateKeyFilePath" ]; then
      printf '      privateKeyFilePath: certs/client.key\n'
    fi
  } >"$OC_ROOT/collectionA/opencollection.yaml"
  run_http_oc_expect_fail --no-interactive -c collectionA get
  [ "$OC_EXIT" -eq 2 ] || {
    echo "FAIL: missing $missing should exit 2, got $OC_EXIT" >&2
    exit 1
  }
  assert_contains "$OC_STDERR" "missing required field: $missing" "error names the missing field ($missing)"
  assert_not_contains "$OC_CURL_ARGS" "--cert" "no curl should run on a malformed entry"
done

# ---------- Test 60: pkcs12 entry exits 2 with not-supported message ----------
echo "test 60: pkcs12 entry exits 2 with not-supported message"
setup_oc_tmp
write_mtls_collection
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pkcs12
      certificateFilePath: certs/client.p12
YAML
run_http_oc_expect_fail --no-interactive -c collectionA get
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: pkcs12 should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "not supported" "pkcs12 message clearly says not supported"
assert_contains "$OC_STDERR" "pkcs12" "pkcs12 message names the type"

# ---------- Test 61: missing certificate/key file exits 2 before any request ----------
echo "test 61: missing certificate or key file exits 2 before any request"
setup_oc_tmp
write_mtls_collection
printf 'fake-key\n' >"$OC_ROOT/collectionA/certs/client.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/missing.pem
      privateKeyFilePath: certs/client.key
YAML
run_http_oc_expect_fail --no-interactive -c collectionA get
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: missing certificate file should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "file not found" "missing certificate file error"
assert_not_contains "$OC_CURL_ARGS" "--cert" "no curl should run when a certificate file is missing"
printf 'fake-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/client.pem
      privateKeyFilePath: certs/missing.key
YAML
run_http_oc_expect_fail --no-interactive -c collectionA get
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: missing key file should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "file not found" "missing key file error"

# ---------- Test 62: host matching no entry behaves exactly as today ----------
echo "test 62: host matching no entry gets no certificate flags"
setup_oc_tmp
write_mtls_collection
printf 'fake-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'fake-key\n' >"$OC_ROOT/collectionA/certs/client.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/client.pem
      privateKeyFilePath: certs/client.key
YAML
cat >"$OC_ROOT/collectionA/requests/other.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://other.example.org/secure
YAML
run_http_oc --no-interactive -c collectionA -n other
assert_not_contains "$OC_STDOUT" "--cert" "unmatched host must not receive certificate flags"
assert_not_contains "$OC_STDOUT" "--key" "unmatched host must not receive key flags"
# a collection with no clientCertificates configured behaves as before
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
YAML
run_http_oc --no-interactive -c collectionA -n other
assert_not_contains "$OC_STDOUT" "--cert" "no certificates configured means no flags"

# ---------- Test 63: module-boundary unit tests for the pure matching rules ----------
echo "test 63: domain_matches_host pure matching rules"
python3 <<'PYEOF'
import importlib.machinery
http = importlib.machinery.SourceFileLoader("http", "general/bin/http").load_module()
m = http.domain_matches_host
# exact
assert m("api.example.com", "api.example.com") is True
# exact never matches a longer host that merely shares a prefix
assert m("api.example.com", "api.example.com.evil.com") is False
# exact never matches a shorter host
assert m("api.example.com", "example.com") is False
# exact never matches a subdomain
assert m("api.example.com", "sub.api.example.com") is False
# wildcard matches subdomains
assert m("*.example.com", "api.example.com") is True
assert m("*.example.com", "a.b.example.com") is True
# wildcard does not match the apex
assert m("*.example.com", "example.com") is False
# wildcard is anchored at the host end
assert m("*.example.com", "notexample.com") is False
# a dot-less wildcard never crosses a label boundary, so no cert leaks to a sharing host
assert m("*example.com", "notexample.com") is False
assert m("*example.com", "example.com") is False
# bare wildcard matches any host
assert m("*", "anything.example.com") is True
# case-insensitive
assert m("API.Example.COM", "api.example.com") is True
# empty inputs never match
assert m("", "example.com") is False
assert m("api.example.com", "") is False
print("OK")
PYEOF

# ---------- Test 64: https-only selection helper ----------
echo "test 64: request_url_https_host https-only"
python3 <<'PYEOF'
import importlib.machinery
http = importlib.machinery.SourceFileLoader("http", "general/bin/http").load_module()
h = http.request_url_https_host
assert h("https://api.example.com/path") == "api.example.com"
assert h("https://Api.Example.com:8443/x") == "api.example.com"
assert h("http://api.example.com/x") is None
assert h("ftp://api.example.com/x") is None
assert h("api.example.com/x") is None
print("OK")
PYEOF

# ---------- Test 65: malformed entry fails even for non-https / unmatched hosts ----------
echo "test 65: malformed entry fails even for non-https and unmatched hosts"
setup_oc_tmp
write_mtls_collection
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pkcs12
      certificateFilePath: certs/client.p12
YAML
cat >"$OC_ROOT/collectionA/requests/plain.yaml" <<'YAML'
type: http
request:
  method: GET
  url: http://api.example.com/secure
YAML
cat >"$OC_ROOT/collectionA/requests/other.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://other.example.org/secure
YAML
run_http_oc_expect_fail --no-interactive -c collectionA plain
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: malformed entry on non-https request should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "not supported" "malformed entry fails on a non-https request too"
run_http_oc_expect_fail --no-interactive -c collectionA other
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: malformed entry on unmatched host should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "not supported" "malformed entry fails even when the host matches nothing"

# ---------- Test 66: environment-only certificate is matched when selected ----------
echo "test 66: environment-only certificate matched when that environment is selected"
setup_oc_tmp
write_mtls_collection
printf 'env-cert\n' >"$OC_ROOT/collectionA/certs/env.pem"
printf 'env-key\n' >"$OC_ROOT/collectionA/certs/env.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  environments:
    - name: production
      clientCertificates:
        - domain: api.example.com
          type: pem
          certificateFilePath: certs/env.pem
          privateKeyFilePath: certs/env.key
YAML
run_http_oc --no-interactive -c collectionA -e production get
assert_contains "$OC_CURL_ARGS" "--cert" "environment certificate reaches executed curl"
assert_contains "$OC_CURL_ARGS" "$OC_ROOT/collectionA/certs/env.pem" "executed curl uses the environment certificate path"
run_http_oc --no-interactive -c collectionA -e production -n get
assert_contains "$OC_STDOUT" "--cert" "dry-run shows the environment certificate"
assert_contains "$OC_STDOUT" "certs/env.pem" "dry-run shows the environment certificate path"
# an unselected environment must not contribute its certificates
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  environments:
    - name: development
      variables:
        - name: baseUrl
          value: https://dev.example.com
    - name: production
      clientCertificates:
        - domain: api.example.com
          type: pem
          certificateFilePath: certs/env.pem
          privateKeyFilePath: certs/env.key
YAML
run_http_oc --no-interactive -c collectionA -e development -n get
assert_not_contains "$OC_STDOUT" "--cert" "unselected environment must not contribute certificates"

# ---------- Test 67: environment entry wins over the collection entry for the same domain ----------
echo "test 67: environment certificate wins over collection for the same domain"
setup_oc_tmp
write_mtls_collection
printf 'coll-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'coll-key\n' >"$OC_ROOT/collectionA/certs/client.key"
printf 'env-cert\n' >"$OC_ROOT/collectionA/certs/env.pem"
printf 'env-key\n' >"$OC_ROOT/collectionA/certs/env.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  environments:
    - name: production
      clientCertificates:
        - domain: api.example.com
          type: pem
          certificateFilePath: certs/env.pem
          privateKeyFilePath: certs/env.key
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/client.pem
      privateKeyFilePath: certs/client.key
YAML
run_http_oc --no-interactive -c collectionA -e production -n get
assert_contains "$OC_STDOUT" "certs/env.pem" "dry-run shows the environment certificate when it wins"
assert_not_contains "$OC_STDOUT" "certs/client.pem" "environment must mask the collection certificate for the same domain"
run_http_oc --no-interactive -c collectionA -e production get
assert_contains "$OC_CURL_ARGS" "certs/env.pem" "executed curl uses the environment certificate"
assert_not_contains "$OC_CURL_ARGS" "certs/client.pem" "collection certificate not used when the environment wins"

# ---------- Test 68: collection certificate applies when env has no entry for its domain ----------
echo "test 68: collection certificate applies when environment defines no entry for its domain"
setup_oc_tmp
write_mtls_collection
printf 'coll-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'coll-key\n' >"$OC_ROOT/collectionA/certs/client.key"
printf 'env-cert\n' >"$OC_ROOT/collectionA/certs/env.pem"
printf 'env-key\n' >"$OC_ROOT/collectionA/certs/env.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  environments:
    - name: production
      clientCertificates:
        - domain: other.example.org
          type: pem
          certificateFilePath: certs/env.pem
          privateKeyFilePath: certs/env.key
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/client.pem
      privateKeyFilePath: certs/client.key
YAML
run_http_oc --no-interactive -c collectionA -e production -n get
assert_contains "$OC_STDOUT" "certs/client.pem" "dry-run shows the collection certificate when it is the only match"
assert_not_contains "$OC_STDOUT" "certs/env.pem" "environment certificate for another domain must not be used"
run_http_oc --no-interactive -c collectionA -e production get
assert_contains "$OC_CURL_ARGS" "certs/client.pem" "executed curl uses the collection certificate when env has no entry for its domain"

# ---------- Test 69: environment entries resolve the full variable context ----------
echo "test 69: environment certificate entries resolve collection/env/request/CLI variables"
setup_oc_tmp
write_mtls_collection
printf 'env-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'env-key\n' >"$OC_ROOT/collectionA/certs/client.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
variables:
  - name: certFileName
    value: client
config:
  environments:
    - name: production
      variables:
        - name: certDomain
          value: api.example.com
      clientCertificates:
        - domain: "{{certDomain}}"
          type: pem
          certificateFilePath: "{{certDir}}/{{certFileName}}.{{certExt}}"
          privateKeyFilePath: "certs/client.key"
YAML
cat >"$OC_ROOT/collectionA/requests/get.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/secure
variables:
  - name: certDir
    value: certs
YAML
run_http_oc --no-interactive -c collectionA -e production -n -v certExt=pem get
assert_contains "$OC_STDOUT" "--cert" "env certificate selected via a templated domain"
assert_contains "$OC_STDOUT" "certs/client.pem" "env/collection/request/CLI variables together resolve the cert path"
run_http_oc --no-interactive -c collectionA -e production -v certExt=pem get
assert_contains "$OC_CURL_ARGS" "certs/client.pem" "executed curl uses the fully-resolved certificate path"

# ---------- Test 70: disabled environment entry skipped without masking the collection entry ----------
echo "test 70: disabled environment entry skipped and does not mask the collection entry"
setup_oc_tmp
write_mtls_collection
printf 'coll-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'coll-key\n' >"$OC_ROOT/collectionA/certs/client.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  environments:
    - name: production
      clientCertificates:
        - domain: api.example.com
          type: pem
          certificateFilePath: certs/disabled.pem
          privateKeyFilePath: certs/disabled.key
          disabled: true
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/client.pem
      privateKeyFilePath: certs/client.key
YAML
run_http_oc --no-interactive -c collectionA -e production get
assert_contains "$OC_CURL_ARGS" "certs/client.pem" "collection certificate used when the environment entry is disabled"
assert_not_contains "$OC_CURL_ARGS" "certs/disabled.pem" "disabled environment entry file never referenced"
run_http_oc --no-interactive -c collectionA -e production -n get
assert_contains "$OC_STDOUT" "certs/client.pem" "dry-run shows the collection certificate behind a disabled env entry"

# ---------- Test 71: module-boundary unit tests for the environment merge rule ----------
echo "test 71: merge_client_certificates environment-wins-per-domain"
python3 <<'PYEOF'
import importlib.machinery
http = importlib.machinery.SourceFileLoader("http", "general/bin/http").load_module()
merge = http.merge_client_certificates


def entry(domain, path, disabled=False):
    e = {"domain": domain, "type": "pem",
         "certificateFilePath": path + ".pem", "privateKeyFilePath": path + ".key"}
    if disabled:
        e["disabled"] = True
    return e


def paths(merged):
    return [e["certificateFilePath"] for e in merged
            if isinstance(e, dict) and "certificateFilePath" in e]

# no environment: the collection list passes through unchanged, in order
merged = merge([entry("a.com", "c1"), entry("b.com", "c2")], [], {})
assert paths(merged) == ["c1.pem", "c2.pem"]
# environment entry with the same domain replaces the collection entry in place
merged = merge([entry("api.example.com", "coll")], [entry("api.example.com", "env")], {})
assert paths(merged) == ["env.pem"]
# collection entry survives when the environment has no entry for its domain
merged = merge([entry("api.example.com", "coll"), entry("*.example.com", "wild")],
               [entry("other.example.org", "env")], {})
assert paths(merged) == ["coll.pem", "wild.pem", "env.pem"]
# environment-only domains are appended in environment order after collection slots
merged = merge([entry("api.example.com", "coll")],
               [entry("a.example.org", "env1"), entry("*.example.com", "env2")], {})
assert paths(merged) == ["coll.pem", "env1.pem", "env2.pem"]
# first environment entry for a domain wins; later duplicates are dropped
merged = merge([], [entry("api.example.com", "e1"), entry("api.example.com", "e2")], {})
assert paths(merged) == ["e1.pem"]
# disabled environment entries claim nothing and never mask the collection entry
merged = merge([entry("api.example.com", "coll")],
               [entry("api.example.com", "env", disabled=True)], {})
assert paths(merged) == ["coll.pem"]
# domains override case-insensitively, matching domain_matches_host semantics
merged = merge([entry("api.example.com", "coll")],
               [entry("API.Example.com", "env")], {})
assert paths(merged) == ["env.pem"]
# a case-insensitive disabled environment entry still claims nothing
merged = merge([entry("api.example.com", "coll")],
               [entry("API.Example.com", "env", disabled=True)], {})
assert paths(merged) == ["coll.pem"]
# domains compare by their resolved (templated) value
merged = merge([entry("{{certDomain}}", "coll1"), entry("api.example.com", "coll2")],
               [entry("api.example.com", "env")], {"certDomain": "api.example.com"})
assert paths(merged) == ["env.pem", "coll2.pem"]
# non-dict entries pass through for clean selection-time validation
merged = merge(["junk"], ["nope"], {})
assert merged == ["junk", "nope"]
print("OK")
PYEOF

# ---------- Test 72: a collection entry masked by the environment is still validated ----------
echo "test 72: collection entry masked by the environment is still validated"
setup_oc_tmp
write_mtls_collection
printf 'env-cert\n' >"$OC_ROOT/collectionA/certs/env.pem"
printf 'env-key\n' >"$OC_ROOT/collectionA/certs/env.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  environments:
    - name: production
      clientCertificates:
        - domain: api.example.com
          type: pem
          certificateFilePath: certs/env.pem
          privateKeyFilePath: certs/env.key
  clientCertificates:
    - domain: api.example.com
      type: pkcs12
      certificateFilePath: certs/old.p12
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -e production get
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: malformed collection entry masked by the environment should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "not supported" "a collection entry masked by the environment is still validated"
assert_contains "$OC_STDERR" "pkcs12" "error names the masked entry's unsupported type"
assert_not_contains "$OC_CURL_ARGS" "--cert" "no curl should run when a masked entry is malformed"
# malformed environment entry also fails even though a collection entry covers the domain
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  environments:
    - name: production
      clientCertificates:
        - domain: api.example.com
          type: pkcs12
          certificateFilePath: certs/env.p12
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/env.pem
      privateKeyFilePath: certs/env.key
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -e production get
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: malformed environment entry should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "not supported" "a malformed environment entry is validated even when the collection covers the domain"
assert_contains "$OC_STDERR" "pkcs12" "error names the environment entry's unsupported type"

# ---------- Test 73: CLI --cert/--key override the manifest cert ----------
echo "test 73: CLI --cert/--key override the manifest cert (executed + dry-run)"
setup_oc_tmp
write_mtls_collection
printf 'manifest-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'manifest-key\n' >"$OC_ROOT/collectionA/certs/client.key"
printf 'cli-cert\n' >"$OC_TMPDIR/cli.pem"
printf 'cli-key\n' >"$OC_TMPDIR/cli.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/client.pem
      privateKeyFilePath: certs/client.key
      passphrase: secret
YAML
run_http_oc --no-interactive -c collectionA --cert "$OC_TMPDIR/cli.pem" --key "$OC_TMPDIR/cli.key" get
assert_contains "$OC_CURL_ARGS" "--cert" "executed curl receives --cert"
assert_contains "$OC_CURL_ARGS" "$OC_TMPDIR/cli.pem" "CLI certificate overrides the manifest match"
assert_contains "$OC_CURL_ARGS" "$OC_TMPDIR/cli.key" "CLI key overrides the manifest match"
assert_not_contains "$OC_CURL_ARGS" "certs/client.pem" "manifest certificate must not appear when overridden"
assert_not_contains "$OC_CURL_ARGS" "--pass" "CLI override drops the manifest passphrase"
run_http_oc --no-interactive -c collectionA -n --cert "$OC_TMPDIR/cli.pem" --key "$OC_TMPDIR/cli.key" get
assert_contains "$OC_STDOUT" "$OC_TMPDIR/cli.pem" "dry-run shows the CLI certificate"
assert_contains "$OC_STDOUT" "$OC_TMPDIR/cli.key" "dry-run shows the CLI key"
assert_not_contains "$OC_STDOUT" "certs/client.pem" "dry-run must not show the manifest certificate"
assert_not_contains "$OC_STDOUT" "--pass" "dry-run CLI override must not show the manifest passphrase"

# ---------- Test 74: --cert without --key (and vice versa) exits 2 ----------
echo "test 74: --cert without --key (and vice versa) exits 2"
setup_oc_tmp
write_mtls_collection
printf 'cli-cert\n' >"$OC_TMPDIR/cli.pem"
printf 'cli-key\n' >"$OC_TMPDIR/cli.key"
run_http_oc_expect_fail --no-interactive -c collectionA --cert "$OC_TMPDIR/cli.pem" get
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: --cert alone should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "--cert and --key must be provided together" "pairing error names both flags"
assert_not_contains "$OC_CURL_ARGS" "--cert" "no curl should run on a pairing error"
run_http_oc_expect_fail --no-interactive -c collectionA --key "$OC_TMPDIR/cli.key" get
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: --key alone should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "--cert and --key must be provided together" "key-alone pairing error names both flags"
assert_not_contains "$OC_CURL_ARGS" "--key" "no curl should run on a key-alone pairing error"

# ---------- Test 75: --cacert adds the CA bundle to the main request ----------
echo "test 75: --cacert adds the CA bundle (executed + dry-run)"
setup_oc_tmp
write_mtls_collection
printf 'ca\n' >"$OC_TMPDIR/ca.pem"
printf 'manifest-cert\n' >"$OC_ROOT/collectionA/certs/client.pem"
printf 'manifest-key\n' >"$OC_ROOT/collectionA/certs/client.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/client.pem
      privateKeyFilePath: certs/client.key
YAML
run_http_oc --no-interactive -c collectionA --cacert "$OC_TMPDIR/ca.pem" get
assert_contains "$OC_CURL_ARGS" "--cacert" "executed curl receives --cacert"
assert_contains "$OC_CURL_ARGS" "$OC_TMPDIR/ca.pem" "executed curl CA bundle path"
assert_contains "$OC_CURL_ARGS" "certs/client.pem" "--cacert co-exists with the manifest client cert"
run_http_oc --no-interactive -c collectionA -n --cacert "$OC_TMPDIR/ca.pem" get
assert_contains "$OC_STDOUT" "--cacert" "dry-run shows --cacert"
assert_contains "$OC_STDOUT" "$OC_TMPDIR/ca.pem" "dry-run shows the CA bundle path"

# ---------- Test 76: -k together with --cacert exits 2 ----------
echo "test 76: -k with --cacert exits 2 (mutually exclusive)"
setup_oc_tmp
write_mtls_collection
printf 'ca\n' >"$OC_TMPDIR/ca.pem"
run_http_oc_expect_fail --no-interactive -c collectionA -k --cacert "$OC_TMPDIR/ca.pem" get
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: -k with --cacert should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "mutually exclusive" "k/cacert contradiction is a clear error"
assert_not_contains "$OC_CURL_ARGS" "--cacert" "no curl should run on a k/cacert contradiction"
run_http_oc_expect_fail --no-interactive -c collectionA --insecure --cacert "$OC_TMPDIR/ca.pem" get
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: --insecure with --cacert should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "mutually exclusive" "--insecure spelling also rejected"

# ---------- Test 77: -k together with --cert/--key works ----------
echo "test 77: -k with --cert/--key works (cert+key only, no --cacert)"
setup_oc_tmp
write_mtls_collection
printf 'cli-cert\n' >"$OC_TMPDIR/cli.pem"
printf 'cli-key\n' >"$OC_TMPDIR/cli.key"
run_http_oc --no-interactive -c collectionA -k --cert "$OC_TMPDIR/cli.pem" --key "$OC_TMPDIR/cli.key" get
assert_contains "$OC_CURL_ARGS" "-k" "-k reaches curl"
assert_contains "$OC_CURL_ARGS" "--cert" "client cert still presented with -k"
assert_contains "$OC_CURL_ARGS" "$OC_TMPDIR/cli.pem" "CLI certificate present with -k"
assert_contains "$OC_CURL_ARGS" "$OC_TMPDIR/cli.key" "CLI key present with -k"
assert_not_contains "$OC_CURL_ARGS" "--cacert" "-k with cert/key must not add --cacert"
run_http_oc --no-interactive -c collectionA -n -k --cert "$OC_TMPDIR/cli.pem" --key "$OC_TMPDIR/cli.key" get
assert_contains "$OC_STDOUT" "-k" "dry-run shows -k"
assert_contains "$OC_STDOUT" "--cert" "dry-run shows the CLI certificate"
assert_not_contains "$OC_STDOUT" "--cacert" "dry-run with -k + cert/key must not show --cacert"

# ---------- Test 78: CLI cert flags do not appear on OAuth2 token requests ----------
echo "test 78: CLI cert flags do not appear on OAuth2 token requests"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
request:
  auth:
    type: oauth2
    grantType: client_credentials
    tokenUrl: https://auth.example.com/token
    clientId: my-client
    clientSecret: my-secret
YAML
cat >"$OC_ROOT/collectionA/requests/secure.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/secure
YAML
printf 'cli-cert\n' >"$OC_TMPDIR/cli.pem"
printf 'cli-key\n' >"$OC_TMPDIR/cli.key"
printf 'ca\n' >"$OC_TMPDIR/ca.pem"
run_http_oc --no-interactive -c collectionA -n --cert "$OC_TMPDIR/cli.pem" --key "$OC_TMPDIR/cli.key" --cacert "$OC_TMPDIR/ca.pem" secure
assert_contains "$OC_CURL_ARGS" "https://auth.example.com/token" "the captured invocation is the token request"
assert_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "token request really ran"
assert_not_contains "$OC_CURL_ARGS" "--cert" "CLI --cert must not reach the token request"
assert_not_contains "$OC_CURL_ARGS" "--key" "CLI --key must not reach the token request"
assert_not_contains "$OC_CURL_ARGS" "--cacert" "CLI --cacert must not reach the token request"
assert_not_contains "$OC_CURL_ARGS" "cli.pem" "CLI cert path must not appear in the token request"
assert_not_contains "$OC_CURL_ARGS" "cli.key" "CLI key path must not appear in the token request"
assert_contains "$OC_STDOUT" "--cert" "main-request dry-run still shows the CLI certificate"
assert_contains "$OC_STDOUT" "--cacert" "main-request dry-run still shows --cacert"

# ---------- Test 79: equivalent command includes cert/key/cacert when used ----------
echo "test 79: equivalent command includes --cert/--key/--cacert"
python3 <<'PYEOF'
import importlib.machinery

http = importlib.machinery.SourceFileLoader("http", "general/bin/http").load_module()
cmd = http.build_equivalent_command(
    "collectionA", "development", "get",
    cert="/certs/cli.pem", key="/certs/cli.key", cacert="/certs/ca.pem",
)
assert "--cert /certs/cli.pem" in cmd, cmd
assert "--key /certs/cli.key" in cmd, cmd
assert "--cacert /certs/ca.pem" in cmd, cmd
# absent flags stay absent
cmd = http.build_equivalent_command("collectionA", "development", "get")
assert "--cert" not in cmd, cmd
assert "--key" not in cmd, cmd
assert "--cacert" not in cmd, cmd
# a manifest-matched certificate needs no CLI flags in the equivalent command
cmd = http.build_equivalent_command(
    "collectionA", "development", "get", cert="/certs/cli.pem",
)
assert "--key" not in cmd and "--cacert" not in cmd, cmd
print("OK")
PYEOF

# ---------- Test 80: client_credentials token call receives cert flags for matching token host ----------
echo "test 80: client_credentials token call receives cert flags for matching token host"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests" "$OC_ROOT/collectionA/certs"
printf 'auth-cert\n' >"$OC_ROOT/collectionA/certs/auth.pem"
printf 'auth-key\n' >"$OC_ROOT/collectionA/certs/auth.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
variables:
  - name: tokenEndpoint
    value: https://auth.example.com/token
config:
  clientCertificates:
    - domain: auth.example.com
      type: pem
      certificateFilePath: certs/auth.pem
      privateKeyFilePath: certs/auth.key
      passphrase: tokensecret
request:
  auth:
    type: oauth2
    grantType: client_credentials
    tokenUrl: "{{tokenEndpoint}}"
    clientId: my-client
    clientSecret: my-secret
YAML
cat >"$OC_ROOT/collectionA/requests/secure.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/secure
YAML
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_CURL_ARGS" "https://auth.example.com/token" "the captured invocation is the token request"
assert_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "token request really ran"
assert_contains "$OC_CURL_ARGS" "--cert" "token call receives --cert"
assert_contains "$OC_CURL_ARGS" "$OC_ROOT/collectionA/certs/auth.pem" "token call uses the matching certificate path"
assert_contains "$OC_CURL_ARGS" "--key" "token call receives --key"
assert_contains "$OC_CURL_ARGS" "$OC_ROOT/collectionA/certs/auth.key" "token call uses the matching key path"
assert_contains "$OC_CURL_ARGS" "--pass" "token call receives --pass"
assert_contains "$OC_CURL_ARGS" "tokensecret" "token call sends the passphrase"
assert_not_contains "$OC_STDOUT" "--cert" "main request host (api.example.com) must not receive the token-host certificate"

# ---------- Test 81: authorization_code token call receives cert flags for matching token host ----------
echo "test 81: authorization_code token call receives cert flags for matching token host"
setup_oc_tmp
cat >"$OC_BIN/auth-code-token" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$AUTH_CODE_ARGS_FILE"
printf '{"access_token":"auth-code-token","token_type":"Bearer","expires_in":3600}\n'
STUB
chmod +x "$OC_BIN/auth-code-token"
export AUTH_CODE_ARGS_FILE="$OC_TMPDIR/auth-code.args"
: >"$AUTH_CODE_ARGS_FILE"
mkdir -p "$OC_ROOT/collectionA/requests" "$OC_ROOT/collectionA/certs"
printf 'auth-cert\n' >"$OC_ROOT/collectionA/certs/auth.pem"
printf 'auth-key\n' >"$OC_ROOT/collectionA/certs/auth.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: auth.example.com
      type: pem
      certificateFilePath: certs/auth.pem
      privateKeyFilePath: certs/auth.key
      passphrase: tokensecret
request:
  auth:
    type: oauth2
    grantType: authorization_code
    authorizationUrl: https://auth.example.com/authorize
    tokenUrl: https://auth.example.com/token
    clientId: browser-client
    scope: openid profile
YAML
cat >"$OC_ROOT/collectionA/requests/browser.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/browser
YAML
run_http_oc --no-interactive -c collectionA -n browser
assert_contains "$AUTH_CODE_ARGS_FILE" "--cert" "helper receives --cert"
assert_contains "$AUTH_CODE_ARGS_FILE" "$OC_ROOT/collectionA/certs/auth.pem" "helper receives the matching certificate path"
assert_contains "$AUTH_CODE_ARGS_FILE" "--key" "helper receives --key"
assert_contains "$AUTH_CODE_ARGS_FILE" "$OC_ROOT/collectionA/certs/auth.key" "helper receives the matching key path"
assert_contains "$AUTH_CODE_ARGS_FILE" "--pass" "helper receives --pass"
assert_contains "$AUTH_CODE_ARGS_FILE" "tokensecret" "helper receives the passphrase"
assert_not_contains "$OC_STDOUT" "--cert" "main request host must not receive the token-host certificate"
run_http_oc --no-interactive -c collectionA -n --auth-no-cache browser
assert_contains "$AUTH_CODE_ARGS_FILE" "--cert" "auth-no-cache refetch passes the certificate to the helper"
assert_contains "$AUTH_CODE_ARGS_FILE" "--force-login" "auth-no-cache still forces login"

# ---------- Test 82: token host matching no entry gets no certificate flags ----------
echo "test 82: token host matching no entry gets no certificate flags"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests" "$OC_ROOT/collectionA/certs"
printf 'api-cert\n' >"$OC_ROOT/collectionA/certs/api.pem"
printf 'api-key\n' >"$OC_ROOT/collectionA/certs/api.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: api.example.com
      type: pem
      certificateFilePath: certs/api.pem
      privateKeyFilePath: certs/api.key
request:
  auth:
    type: oauth2
    grantType: client_credentials
    tokenUrl: https://auth.example.com/token
    clientId: my-client
    clientSecret: my-secret
YAML
cat >"$OC_ROOT/collectionA/requests/secure.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/secure
YAML
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_CURL_ARGS" "https://auth.example.com/token" "the captured invocation is the token request"
assert_not_contains "$OC_CURL_ARGS" "--cert" "token host matching nothing must not receive cert flags"
assert_not_contains "$OC_CURL_ARGS" "--key" "token host matching nothing must not receive key flags"
assert_not_contains "$OC_CURL_ARGS" "--pass" "token host matching nothing must not receive pass flags"
assert_contains "$OC_STDOUT" "--cert" "main request host still receives its own certificate"

# ---------- Test 83: environment-level certificates apply to token matching ----------
echo "test 83: environment-level certificates apply to token matching like the main request"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests" "$OC_ROOT/collectionA/certs"
printf 'env-auth-cert\n' >"$OC_ROOT/collectionA/certs/auth.pem"
printf 'env-auth-key\n' >"$OC_ROOT/collectionA/certs/auth.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  environments:
    - name: development
      variables:
        - name: baseUrl
          value: https://dev.example.com
    - name: production
      variables:
        - name: baseUrl
          value: https://prod.example.com
      clientCertificates:
        - domain: auth.example.com
          type: pem
          certificateFilePath: certs/auth.pem
          privateKeyFilePath: certs/auth.key
request:
  auth:
    type: oauth2
    grantType: client_credentials
    tokenUrl: https://auth.example.com/token
    clientId: my-client
    clientSecret: my-secret
YAML
cat >"$OC_ROOT/collectionA/requests/secure.yaml" <<'YAML'
type: http
request:
  method: GET
  url: "{{baseUrl}}/secure"
YAML
# development environment has no certificates for the token host
run_http_oc --no-interactive -c collectionA -e development -n secure
assert_contains "$OC_CURL_ARGS" "https://auth.example.com/token" "the captured invocation is the token request"
assert_not_contains "$OC_CURL_ARGS" "--cert" "environment without certificates must not produce token cert flags"
# production environment's certificate matches the token host
run_http_oc --no-interactive -c collectionA -e production -n secure
assert_contains "$OC_CURL_ARGS" "https://auth.example.com/token" "the captured invocation is the token request"
assert_contains "$OC_CURL_ARGS" "--cert" "environment certificate reaches the token call"
assert_contains "$OC_CURL_ARGS" "$OC_ROOT/collectionA/certs/auth.pem" "token call uses the environment certificate path"
assert_contains "$OC_STDOUT" "https://prod.example.com/secure" "selected environment still resolves the main request"

# ---------- Test 84: cached token skips the token curl call; --auth-no-cache refetches with the certificate ----------
echo "test 84: cached token skips the token curl call; --auth-no-cache refetches with the certificate"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests" "$OC_ROOT/collectionA/certs"
printf 'auth-cert\n' >"$OC_ROOT/collectionA/certs/auth.pem"
printf 'auth-key\n' >"$OC_ROOT/collectionA/certs/auth.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: auth.example.com
      type: pem
      certificateFilePath: certs/auth.pem
      privateKeyFilePath: certs/auth.key
request:
  auth:
    type: oauth2
    grantType: client_credentials
    tokenUrl: https://auth.example.com/token
    clientId: my-client
    clientSecret: my-secret
YAML
cat >"$OC_ROOT/collectionA/requests/secure.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/secure
YAML
# first run: no cache, token fetched with the certificate
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "first run fetches the token"
assert_contains "$OC_CURL_ARGS" "--cert" "first run presents the certificate"
# cached run: the token curl call is skipped entirely, certificates configured or not
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_STDOUT" "Authorization: Bearer ***" "cached token reused"
assert_not_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "cached token skips the token curl call"
assert_not_contains "$OC_CURL_ARGS" "--cert" "no token curl call means no certificate flags"
# --auth-no-cache forces a refetch that applies the matching certificate
run_http_oc --no-interactive -c collectionA -n --auth-no-cache secure
assert_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "auth-no-cache refetches the token"
assert_contains "$OC_CURL_ARGS" "--cert" "refetch applies the matching certificate"
assert_contains "$OC_CURL_ARGS" "$OC_ROOT/collectionA/certs/auth.pem" "refetch uses the certificate path"

# ---------- Test 85: missing token-certificate file exits 2 before any token curl ----------
echo "test 85: missing token-certificate file exits 2 before any token curl"
setup_oc_tmp
mkdir -p "$OC_ROOT/collectionA/requests" "$OC_ROOT/collectionA/certs"
printf 'fake-key\n' >"$OC_ROOT/collectionA/certs/auth.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: auth.example.com
      type: pem
      certificateFilePath: certs/missing.pem
      privateKeyFilePath: certs/auth.key
request:
  auth:
    type: oauth2
    grantType: client_credentials
    tokenUrl: https://auth.example.com/token
    clientId: my-client
    clientSecret: my-secret
YAML
cat >"$OC_ROOT/collectionA/requests/secure.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/secure
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -n secure
[ "$OC_EXIT" -eq 2 ] || {
  echo "FAIL: missing token certificate file should exit 2, got $OC_EXIT" >&2
  exit 1
}
assert_contains "$OC_STDERR" "file not found" "missing token certificate file error"
assert_not_contains "$OC_STDERR" "Traceback" "missing token cert must not traceback"
assert_not_contains "$OC_CURL_ARGS" "--cert" "no token curl should run when the certificate file is missing"
assert_not_contains "$OC_CURL_ARGS" "grant_type=client_credentials" "no token curl should run when the certificate file is missing"

# CLI --cert/--key must keep staying off token requests when a manifest cert matches the token host
mkdir -p "$OC_ROOT/collectionA/certs"
printf 'cli-cert\n' >"$OC_TMPDIR/cli.pem"
printf 'cli-key\n' >"$OC_TMPDIR/cli.key"
printf 'auth-cert\n' >"$OC_ROOT/collectionA/certs/auth.pem"
printf 'auth-key\n' >"$OC_ROOT/collectionA/certs/auth.key"
cat >"$OC_ROOT/collectionA/opencollection.yaml" <<'YAML'
info:
  name: collectionA
config:
  clientCertificates:
    - domain: auth.example.com
      type: pem
      certificateFilePath: certs/auth.pem
      privateKeyFilePath: certs/auth.key
request:
  auth:
    type: oauth2
    grantType: client_credentials
    tokenUrl: https://auth.example.com/token
    clientId: my-client
    clientSecret: my-secret
YAML
cat >"$OC_ROOT/collectionA/requests/secure.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/secure
YAML
run_http_oc --no-interactive -c collectionA -n --cert "$OC_TMPDIR/cli.pem" --key "$OC_TMPDIR/cli.key" secure
assert_contains "$OC_CURL_ARGS" "https://auth.example.com/token" "the captured invocation is the token request"
assert_contains "$OC_CURL_ARGS" "--cert" "manifest certificate still reaches the token call"
assert_contains "$OC_CURL_ARGS" "certs/auth.pem" "token call uses the manifest certificate, not the CLI one"
assert_not_contains "$OC_CURL_ARGS" "cli.pem" "CLI certificate must not leak into the token call"
assert_not_contains "$OC_CURL_ARGS" "cli.key" "CLI key must not leak into the token call"
assert_contains "$OC_STDOUT" "--cert" "main-request dry-run shows the CLI certificate"
assert_contains "$OC_STDOUT" "$OC_TMPDIR/cli.pem" "main-request dry-run shows the CLI certificate path"

# ---------- Test 86: module-boundary unit tests for the token cert flag builder ----------
echo "test 86: _token_cert_flags pure builder"
python3 <<'PYEOF'
import importlib.machinery

http = importlib.machinery.SourceFileLoader("http", "general/bin/http").load_module()

assert http._token_cert_flags(None) == []
flags = http._token_cert_flags({
    "domain": "auth.example.com",
    "certificate": "/certs/token.pem",
    "key": "/certs/token.key",
    "passphrase": "secret",
})
assert flags == ["--cert", "/certs/token.pem", "--key", "/certs/token.key", "--pass", "secret"], flags
flags = http._token_cert_flags({
    "domain": "auth.example.com",
    "certificate": "/certs/token.pem",
    "key": "/certs/token.key",
    "passphrase": None,
})
assert flags == ["--cert", "/certs/token.pem", "--key", "/certs/token.key"], flags
flags = http._token_cert_flags({
    "domain": "auth.example.com",
    "certificate": "/certs/token.pem",
    "key": "/certs/token.key",
    "passphrase": "",
})
assert flags == ["--cert", "/certs/token.pem", "--key", "/certs/token.key"], flags
print("OK")
PYEOF

# auth-code-token rejects --cert/--key/--pass pairing mistakes before any auth flow
HELPER="$(dirname "$SCRIPT")/auth-code-token"
HELPER_EXIT=0
"$HELPER" client https://auth.example.com/authorize https://auth.example.com/token --key key.pem >/dev/null 2>"$OC_TMPDIR/helper-key-only.err" || HELPER_EXIT=$?
[ "$HELPER_EXIT" -eq 1 ] || {
  echo "FAIL: helper --key alone should exit 1, got $HELPER_EXIT" >&2
  exit 1
}
assert_contains "$OC_TMPDIR/helper-key-only.err" "--cert and --key must be provided together" "helper rejects --key alone"
HELPER_EXIT=0
"$HELPER" client https://auth.example.com/authorize https://auth.example.com/token --cert cert.pem >/dev/null 2>"$OC_TMPDIR/helper-cert-only.err" || HELPER_EXIT=$?
[ "$HELPER_EXIT" -eq 1 ] || {
  echo "FAIL: helper --cert alone should exit 1, got $HELPER_EXIT" >&2
  exit 1
}
assert_contains "$OC_TMPDIR/helper-cert-only.err" "--cert and --key must be provided together" "helper rejects --cert alone"
HELPER_EXIT=0
"$HELPER" client https://auth.example.com/authorize https://auth.example.com/token --pass secret >/dev/null 2>"$OC_TMPDIR/helper-pass-only.err" || HELPER_EXIT=$?
[ "$HELPER_EXIT" -eq 1 ] || {
  echo "FAIL: helper --pass alone should exit 1, got $HELPER_EXIT" >&2
  exit 1
}
assert_contains "$OC_TMPDIR/helper-pass-only.err" "--pass requires --cert and --key" "helper rejects --pass without a certificate"
assert_not_contains "$OC_TMPDIR/helper-pass-only.err" "Traceback" "helper pairing error must not traceback"
assert_not_contains "$OC_TMPDIR/helper-pass-only.err" "Opening browser" "pairing error must stop before any auth flow"

echo "OK"
