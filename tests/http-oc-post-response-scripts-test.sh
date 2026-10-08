#!/usr/bin/env bash
# tier: slow
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
variables:
  - name: source
    value: collection
config:
  environments:
    - name: test
      variables:
        - name: source
          value: environment
YAML
cat >"$TMP/collections/demo/requests/inspect.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/inspect
variables:
  - name: source
    value: request
runtime:
  scripts:
    - type: after-response
      code: |
        console.log("diagnostic", res.status);
        if (res.getStatus() !== 500) throw new Error("status mismatch");
        if (res.body.answer !== 42) throw new Error("body mismatch");
        if (res.getHeader("x-test") !== "yes") throw new Error("header mismatch");
        if (bru.getVar("source") !== "environment") throw new Error("resolved variable mismatch");
        if (bru.getProcessEnv("HTTP_OC_TEST_ENV") !== "inherited") throw new Error("process env mismatch");
        bru.setVar("token", res.body.answer.toString());
    - type: after-response
      code: |
        if (bru.getVar("token") !== "42") throw new Error("runtime variable was not shared");
        bru.setVar("token", "second");
        console.log("runtime", bru.getVar("token"));
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
cat >"$TMP/collections/demo/requests/export.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/export
runtime:
  scripts:
    - type: after-response
      code: |
        bru.setVar("token", `line one
        quote ' and "\$(touch /tmp/http-oc-export-pwned)`);
YAML
cat >"$TMP/collections/demo/requests/renew.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/renew
runtime:
  scripts:
    - type: after-response
      code: bru.setVar("renewed", "renewed value");
YAML
cat >"$TMP/collections/demo/requests/multiple.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/multiple
runtime:
  scripts:
    - type: after-response
      code: |
        bru.setVar("token", "token value");
        bru.setVar("account", "account value");
YAML
cat >"$TMP/collections/demo/requests/multiple-fail.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/multiple-fail
runtime:
  scripts:
    - type: after-response
      code: |
        bru.setVar("token", "new token");
    - type: after-response
      code: throw new Error("later export failure");
YAML
cat >"$TMP/collections/demo/requests/multiple-invalid.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/multiple-invalid
runtime:
  scripts:
    - type: after-response
      code: |
        bru.setVar("token", "new token");
        bru.setVar("account", 42);
YAML
cat >"$TMP/collections/demo/requests/multiple-timeout.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/multiple-timeout
runtime:
  scripts:
    - type: after-response
      code: |
        bru.setVar("token", "new token");
        bru.setVar("account", "new account");
        const started = Date.now();
        while (Date.now() - started < 11000) {}
YAML
cat >"$TMP/collections/demo/requests/multiple-missing.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/multiple-missing
runtime:
  scripts:
    - type: after-response
      code: bru.setVar("token", "new token");
YAML
cat >"$TMP/collections/demo/requests/empty.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/empty
runtime:
  scripts:
    - type: after-response
      code: bru.setVar("empty", "");
YAML
cat >"$TMP/collections/demo/requests/rejected.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/rejected
runtime:
  scripts:
    - type: after-response
      code: bru.setVar("value", 42);
YAML
cat >"$TMP/collections/demo/requests/failure-preserves.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/failure-preserves
runtime:
  scripts:
    - type: after-response
      code: |
        bru.setVar("token", "replacement");
        throw new Error("export failure");
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
  HOME="$TMP/home" PATH="$TMP/bin:$PATH" HTTP_OC_TEST_ENV=inherited "$SCRIPT" oc --no-interactive -c demo "$@"
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
set +e
run --allow-scripts -e test inspect >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -eq 0 ]] || { cat "$TMP/err" >&2; exit 1; }
assert_contains "$TMP/out" '"answer":42' "response should remain on stdout"
assert_contains "$TMP/err" "diagnostic 500" "console.log should use stderr"
assert_contains "$TMP/err" "runtime second" "later scripts should see and overwrite runtime variables"
assert_not_contains "$TMP/out" "diagnostic" "diagnostics should not contaminate stdout"
[[ $(grep -c 'https://example.test/inspect' "$TMP/calls") -eq 1 ]]

# Runtime variables are temporary and do not survive another invocation;
# collection and Environment documents are unchanged by script execution.
manifest_before=$(shasum "$TMP/collections/demo/opencollection.yaml")
cat >"$TMP/collections/demo/requests/not-shared.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/not-shared
runtime:
  scripts:
    - type: after-response
      code: |
        if (bru.getVar("token") !== undefined) throw new Error("runtime state leaked");
YAML
run --allow-scripts not-shared >"$TMP/out" 2>"$TMP/err"
[[ "$manifest_before" == "$(shasum "$TMP/collections/demo/opencollection.yaml")" ]]

# Script failure is nonzero without hiding the received response.
set +e
run --allow-scripts fail >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -ne 0 ]]
assert_contains "$TMP/out" '"answer":42' "failed script must preserve response output"
assert_contains "$TMP/err" "rejected response" "script exception should be visible"

# A later script failure prevents subsequent scripts from running.
cat >"$TMP/collections/demo/requests/later-fail.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://example.test/later-fail
runtime:
  scripts:
    - type: after-response
      code: bru.setVar("beforeFailure", "yes");
    - type: after-response
      code: throw new Error("later failure");
    - type: after-response
      code: console.log("must not run");
YAML
set +e
run --allow-scripts later-fail >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -ne 0 ]]
assert_contains "$TMP/err" "later failure" "later script failure should be visible"
assert_not_contains "$TMP/err" "must not run" "scripts after a failure must not run"

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
      code: |
        { const started = Date.now();
          while (Date.now() - started < 6000) {} }
    - type: after-response
      code: |
        { const started = Date.now();
          while (Date.now() - started < 6000) {} }
YAML
# The execution limit is driven down to one second here so the bounded
# failure is asserted quickly; the busy-loop fixture is unchanged.
set +e
HTTP_OC_SCRIPT_TIMEOUT_SECONDS=1 run --allow-scripts timeout >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -ne 0 ]]
assert_contains "$TMP/err" "1-second execution limit" "timeout should fail clearly"
# --export requires the separately loaded zsh integration and does not
# authorize scripts by itself.
: >"$TMP/calls"
set +e
run --export TOKEN=token inspect >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -eq 2 ]]
assert_contains "$TMP/err" "--allow-scripts" "export must not authorize scripts"
[[ ! -s "$TMP/calls" ]]
set +e
run --allow-scripts --export TOKEN=token inspect >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -eq 2 ]]
assert_contains "$TMP/err" "zsh integration" "export should require zsh integration"
[[ ! -s "$TMP/calls" ]]

# Mapping syntax and duplicate mappings are rejected before curl.
for mapping_args in "BAD-NAME=token" "TOKEN" "TOKEN="; do
  : >"$TMP/calls"
  set +e
  run --allow-scripts --export "$mapping_args" inspect >"$TMP/out" 2>"$TMP/err"
  status=$?
  set -e
  [[ $status -eq 2 ]]
  [[ ! -s "$TMP/calls" ]]
done
: >"$TMP/calls"
set +e
run --allow-scripts --export TOKEN=token --export TOKEN=token inspect >"$TMP/out" 2>"$TMP/err"
status=$?
set -e
[[ $status -eq 2 ]]
assert_contains "$TMP/err" "selected once" "duplicate export destinations should be rejected"
[[ ! -s "$TMP/calls" ]]

# The zsh integration transfers literal data to the calling shell, including
# hostile-looking characters, and a subsequent child sees the new value.
export ZSH_INTEGRATION="$PWD/zsh/.http-oc.zsh"
export PATH="$TMP/bin:$(dirname "$SCRIPT"):$PATH"
set +e
HTTP_OC_SCRIPT_TIMEOUT_SECONDS=1 HOME="$TMP/home" zsh -fc 'source "$1"; export TOKEN=old-token; export ACCOUNT=old-account; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token --export ACCOUNT=account multiple-timeout >/dev/null 2>"$2"' 'zsh-test' "$ZSH_INTEGRATION" "$TMP/err"
status=$?
set -e
[[ $status -ne 0 ]]
assert_contains "$TMP/err" "1-second execution limit" "multi-export timeout should fail clearly"
rm -f /tmp/http-oc-export-pwned
HOME="$TMP/home" zsh -fc 'source "$1"; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token export >/dev/null; sh -c '\''printf "%s" "$TOKEN"'\''' 'zsh-test' "$ZSH_INTEGRATION" >"$TMP/exported" 2>"$TMP/err"
expected=$'line one\nquote \' and "$(touch /tmp/http-oc-export-pwned)'
[[ "$(cat "$TMP/exported")" == "$expected" ]]
[[ ! -e /tmp/http-oc-export-pwned ]]

# A later invocation can renew the same destination in that shell.
HOME="$TMP/home" zsh -fc 'source "$1"; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token export >/dev/null; http oc --no-interactive -c demo --allow-scripts --export TOKEN=renewed renew >/dev/null; sh -c '\''printf "%s" "$TOKEN"'\''' 'zsh-test' "$ZSH_INTEGRATION" >"$TMP/renewed" 2>"$TMP/err"
[[ "$(cat "$TMP/renewed")" == "renewed value" ]]

# Multiple exports are applied as one selected set, including names that
# overlap helper implementation details.
HOME="$TMP/home" zsh -fc 'set -u; source "$1"; http oc --no-interactive -c demo --allow-scripts --export value=token --export transfer=account multiple >/dev/null; sh -c '\''printf "%s|%s" "$value" "$transfer"'\''' 'zsh-test' "$ZSH_INTEGRATION" >"$TMP/multiple"
[[ "$(cat "$TMP/multiple")" == "token value|account value" ]]

# Empty strings are valid export values.
HOME="$TMP/home" zsh -fc 'source "$1"; http oc --no-interactive -c demo --allow-scripts --export TOKEN=empty empty >/dev/null; [[ -v TOKEN && "$TOKEN" == "" ]]' 'zsh-test' "$ZSH_INTEGRATION"

# Non-string values and missing assignments are rejected without curl-side
# success being treated as an export.
set +e
HOME="$TMP/home" zsh -fc 'source "$1"; http oc --no-interactive -c demo --allow-scripts --export TOKEN=value rejected' 'zsh-test' "$ZSH_INTEGRATION" >/dev/null 2>"$TMP/err"
status=$?
set -e
[[ $status -ne 0 ]]
assert_contains "$TMP/err" "not assigned a string" "non-string export should fail"

# Script rejection never changes an already exported, unexported, or absent
# destination state.
HOME="$TMP/home" zsh -fc 'source "$1"; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token export >/dev/null; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token failure-preserves >/dev/null 2>/dev/null; test "$TOKEN" = "$2"' 'zsh-test' "$ZSH_INTEGRATION" "$expected"
HOME="$TMP/home" zsh -fc 'source "$1"; export TOKEN=old-token; ACCOUNT=old-account; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token --export ACCOUNT=account multiple-fail >/dev/null 2>/dev/null; test "$TOKEN" = old-token; test "$ACCOUNT" = old-account' 'zsh-test' "$ZSH_INTEGRATION"
HOME="$TMP/home" zsh -fc 'source "$1"; export TOKEN=old-token; typeset +x ACCOUNT=old-account; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token --export ACCOUNT=account multiple-invalid >/dev/null 2>/dev/null; test "$TOKEN" = old-token; test "$ACCOUNT" = old-account; [[ "${parameters[ACCOUNT]}" != *export* ]]' 'zsh-test' "$ZSH_INTEGRATION"
HOME="$TMP/home" zsh -fc 'source "$1"; export TOKEN=old-token; typeset -r ACCOUNT=old-account; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token --export ACCOUNT=account multiple >/dev/null 2>/dev/null; test "$TOKEN" = old-token; test "$ACCOUNT" = old-account; [[ "${parameters[TOKEN]}" == *export* ]]' 'zsh-test' "$ZSH_INTEGRATION"
HOME="$TMP/home" zsh -fc 'source "$1"; export TOKEN=old-token; unset ACCOUNT; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token --export ACCOUNT=missing multiple-missing >/dev/null 2>/dev/null; test "$TOKEN" = old-token; [[ ! -v ACCOUNT ]]' 'zsh-test' "$ZSH_INTEGRATION"
HOME="$TMP/home" zsh -fc 'typeset +x TOKEN=local; source "$1"; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token failure-preserves >/dev/null 2>/dev/null; test "$TOKEN" = local; [[ -z "${parameters[TOKEN][export]}" ]]' 'zsh-test' "$ZSH_INTEGRATION"
HOME="$TMP/home" zsh -fc 'unset TOKEN; source "$1"; http oc --no-interactive -c demo --allow-scripts --export TOKEN=token failure-preserves >/dev/null 2>/dev/null; [[ ! -v TOKEN ]]' 'zsh-test' "$ZSH_INTEGRATION"

# Successful HTTP transport is insufficient when the post-response script fails.
# The zsh boundary preserves the prior value; script diagnostics stay on the
# redirected stderr for the failing invocation.

echo "OK"
