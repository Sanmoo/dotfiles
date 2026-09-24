#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/http"
assert_contains() { grep -Fq -- "$2" "$1" || { echo "FAIL: $3" >&2; cat "$1" >&2; exit 1; }; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || { echo "FAIL: $3" >&2; cat "$1" >&2; exit 1; }; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.config" "$TMP/bin" "$TMP/collections/demo/requests"
cat >"$TMP/home/.config/.httprc" <<EOF
collections:
  - $TMP/collections
EOF
cat >"$TMP/collections/demo/opencollection.yaml" <<'YAML'
info:
  name: demo
YAML
cat >"$TMP/collections/demo/requests/inspect.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/inspect
runtime:
  scripts:
    - type: after-response
      code: |
        console.log("diagnostic", res.status);
        if (res.getStatus() !== 500) throw new Error("status mismatch");
        if (res.body.answer !== 42) throw new Error("body mismatch");
        if (res.getHeader("x-test") !== "yes") throw new Error("header mismatch");
YAML
cat >"$TMP/collections/demo/requests/fail.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/fail
runtime:
  scripts:
    - type: after-response
      code: throw new Error("rejected response");
YAML
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CURL_CALLS"
if [[ "$*" == *transport* ]]; then exit 7; fi
header_file=""
body_file=""
while (($#)); do
  if [[ "$1" == "--dump-header" ]]; then header_file="$2"; shift 2; continue; fi
  if [[ "$1" == "--output" ]]; then body_file="$2"; shift 2; continue; fi
  shift
done
printf 'HTTP/1.1 500 Internal Server Error\r\nX-Test: yes\r\n\r\n' >"$header_file"
printf '{"answer":42}\n' >"$body_file"
SH
chmod +x "$TMP/bin/curl"
export CURL_CALLS="$TMP/calls"

run() {
  HOME="$TMP/home" PATH="$TMP/bin:$PATH" "$SCRIPT" oc --no-interactive -c demo "$@"
}

# Authorization is checked before curl is invoked.
set +e
run inspect >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -eq 2 ]]
assert_contains "$TMP/err" "--allow-scripts" "missing authorization should be clear"
[[ ! -s "$TMP/calls" ]]

# A complete HTTP error reaches the script; response stays stdout and logs stderr.
: >"$TMP/calls"
run --allow-scripts inspect >"$TMP/out" 2>"$TMP/err"
assert_contains "$TMP/out" '"answer":42' "response should remain on stdout"
assert_contains "$TMP/err" "diagnostic 500" "console.log should use stderr"
assert_not_contains "$TMP/out" "diagnostic" "diagnostics should not contaminate stdout"

# Script failure is nonzero without hiding the received response.
set +e
run --allow-scripts fail >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -ne 0 ]]
assert_contains "$TMP/out" '"answer":42' "failed script must preserve response output"
assert_contains "$TMP/err" "rejected response" "script exception should be visible"

# A transport failure does not invoke the script.
cat >"$TMP/collections/demo/requests/transport.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/transport
runtime:
  scripts:
    - type: after-response
      code: throw new Error("must not run");
YAML
: >"$TMP/calls"
set +e
run --allow-scripts transport >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -eq 7 ]]
assert_not_contains "$TMP/err" "must not run" "transport failure must skip scripts"

# Unsupported lifecycle and multiple scripts fail before curl.
cat >"$TMP/collections/demo/requests/unsupported.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/unsupported
runtime:
  scripts:
    - type: before-request
      code: console.log("no");
YAML
: >"$TMP/calls"
set +e
run --allow-scripts unsupported >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -eq 2 ]]
assert_contains "$TMP/err" "unsupported runtime script type" "unsupported lifecycle should be rejected"
[[ ! -s "$TMP/calls" ]]

# Unsupported JavaScript API and the execution timeout are failures.
cat >"$TMP/collections/demo/requests/unsupported-api.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/unsupported-api
runtime:
  scripts:
    - type: after-response
      code: require("fs");
YAML
set +e
run --allow-scripts unsupported-api >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -ne 0 ]]
assert_contains "$TMP/err" "require is not defined" "unsupported API should fail clearly"
cat >"$TMP/collections/demo/requests/timeout.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/timeout
runtime:
  scripts:
    - type: after-response
      code: while (true) {}
YAML
set +e
run --allow-scripts timeout >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -ne 0 ]]
assert_contains "$TMP/err" "10-second execution limit" "timeout should fail clearly"

# --export is intentionally rejected in this vertical slice.
: >"$TMP/calls"
set +e
run --export TOKEN=token inspect >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -eq 2 ]]
assert_contains "$TMP/err" "--export is not supported yet" "export should fail before sending"
[[ ! -s "$TMP/calls" ]]

echo "OK"
