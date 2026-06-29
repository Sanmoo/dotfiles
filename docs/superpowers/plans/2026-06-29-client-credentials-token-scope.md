# `client-credentials-token` Optional Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional 4th positional `scope` argument to `general/bin/client-credentials-token` that is sent in the OAuth2 token request form body when provided, and cover the new behavior with shell tests.

**Architecture:** Keep the script's positional-argument style and add a single optional 4th argument. Internally, build the `curl` command line as a bash array so the scope flag can be appended conditionally, and use `curl --data-urlencode` for the scope so that space-separated multi-scope values are encoded per `application/x-www-form-urlencoded`. Refactor the existing single-scenario test file into a small helper-based harness that runs the script with stubbed `curl` and asserts on the captured curl arguments across multiple scenarios.

**Tech Stack:** Bash (script under change), shell test in `tests/`, `curl` and `jq` at runtime (unchanged).

## Global Constraints

- Production file: `general/bin/client-credentials-token` (bash, `set -euo pipefail`).
- Test file: `tests/client-credentials-token-test.sh`.
- Argument counts accepted: exactly 3 (current behavior) or exactly 4 (new). Any other count exits non-zero with the updated `Usage:` line.
- 4th argument, when present and non-empty after whitespace normalization, is sent as `scope=<value>` via `curl --data-urlencode`. Otherwise the `scope` parameter is omitted entirely from the form body.
- Whitespace-only 4th argument (e.g. `"   "`) is normalized to empty and treated as "no scope" (no error).
- Backward compatibility: any existing 3-argument invocation must produce an identical curl invocation and identical stdout/stderr behavior.
- No new dependencies. `curl` and `jq` remain the only runtime requirements.
- No new CLI flags. Positionals only. No `getopts` / no flag parser.
- TDD: write the failing test scenarios first, run to confirm they fail in the expected way, then implement, then run to confirm all pass.
- Commit the test file and the script change in a single commit so the diff is reviewable as a unit.

## File Structure

| File | Responsibility |
| --- | --- |
| `general/bin/client-credentials-token` | Bash OAuth2 client_credentials grant CLI. Adds optional 4th positional `scope` argument; switches to a bash array for `curl` arguments; conditionally appends `--data-urlencode scope=<value>`. |
| `tests/client-credentials-token-test.sh` | Shell test that stubs `curl` with a tiny shell script capturing the arguments to a per-scenario file, then asserts on those arguments. Refactored into a `run_scenario` helper that supports multiple scenarios. |

---

## Task 1: Add optional scope support with shell test coverage

**Files:**

- Modify: `general/bin/client-credentials-token` (full file rewrite — script is small, ~36 lines)
- Modify: `tests/client-credentials-token-test.sh` (refactor to a helper-based harness and add 3 scope scenarios)

**Interfaces:**

- Consumes: shell `curl` and `jq` commands on `PATH`; runtime arguments `client_id`, `client_secret`, `token_url`, optional `scope`.
- Produces: prints the `access_token` returned by the token endpoint to stdout; on failure prints to stderr and exits non-zero.

### Step 1: Refactor the test file into a helper-based harness and add the 3 scope scenarios (failing tests first)

Replace `tests/client-credentials-token-test.sh` with the following content. The new harness has a `run_scenario` helper that:

- creates a per-scenario stub directory
- writes a stub `curl` that records its arguments to a per-scenario file
- runs the script with the stubbed `curl` first on `PATH`

After the helper, the file runs 4 scenarios in order: the original 3-arg regression case (renamed `default`) plus 3 new scope cases. The scope cases will fail with the current script because it only accepts exactly 3 arguments.

```bash
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
```

### Step 2: Run the test file and confirm the new scope scenarios fail with the current script

Run:

```bash
bash tests/client-credentials-token-test.sh
```

Expected: the script exits non-zero. The first failing assertion will be in either the `with-scope` or `empty-scope` or `whitespace-scope` scenario, because the current script only accepts exactly 3 positional arguments and prints the `Usage:` message to stderr and exits 1.

To confirm the failure mode is what we expect, run again and inspect the output:

```bash
bash tests/client-credentials-token-test.sh 2>&1 | tail -20
```

Expected output (approximately): a message such as `Expected with-scope to exit 0, got 1` followed by the `--- stderr ---` block showing the `Usage: client-credentials-token <client_id> <client_secret> <token_url>` heredoc. This is the expected red state.

### Step 3: Replace `general/bin/client-credentials-token` with the scope-aware version

Replace the entire file `general/bin/client-credentials-token` with the following content. The script is small enough that a full rewrite is clearer than a series of small diffs.

```bash
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ] && [ "$#" -ne 4 ]; then
  cat >&2 <<'USAGE'
Usage: client-credentials-token <client_id> <client_secret> <token_url> [scope]
USAGE
  exit 1
fi

for command in curl jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Error: required command '$command' not found" >&2
    exit 1
  fi
done

CLIENT_ID="$1"
CLIENT_SECRET="$2"
TOKEN_URL="$3"
SCOPE="${4:-}"

# A scope that is empty or consists solely of spaces is treated as "no scope".
if [ -z "${SCOPE// /}" ]; then
  SCOPE=""
fi

CURL_ARGS=(
  --silent --show-error --fail
  -X POST
  "$TOKEN_URL"
  -H 'Content-Type: application/x-www-form-urlencoded'
  -d 'grant_type=client_credentials'
  -d "client_id=$CLIENT_ID"
  -d "client_secret=$CLIENT_SECRET"
)

if [ -n "$SCOPE" ]; then
  CURL_ARGS+=(--data-urlencode "scope=$SCOPE")
fi

response="$(curl "${CURL_ARGS[@]}")"

token="$(printf '%s' "$response" | jq -r '.access_token // empty')"

if [ -z "$token" ]; then
  echo "Error: access_token not found in token response" >&2
  exit 1
fi

printf '%s\n' "$token"
```

Notes on the rewrite (in code-review order):

- The argument-count guard now accepts `3` or `4` and the heredoc adds the `[scope]` suffix.
- `SCOPE="${4:-}"` avoids `set -u` failures when only 3 args are passed.
- `${SCOPE// /}` strips every space; if the result is empty, the original value was empty or whitespace-only, so `SCOPE` is reset to `""` and the conditional `if [ -n "$SCOPE" ]` is false, which means the `scope` parameter is omitted entirely from the form body.
- The `curl` arguments are built as a bash array so `--data-urlencode scope=$SCOPE` can be appended only when needed.
- `--data-urlencode` is used specifically for the scope because `curl -d` does not URL-encode; a value like `read write` must be transmitted as `read+write` (form-urlencoded), which `--data-urlencode` produces.
- The token extraction, the `jq` dependency check, and the `printf '%s\n' "$token"` output are unchanged.

### Step 4: Run the test file and confirm all 4 scenarios pass

Run:

```bash
bash tests/client-credentials-token-test.sh
```

Expected: the script exits 0 with no output on stdout. All 4 scenarios pass:

- `default` — 3 args, no `scope=` in curl args, no `--data-urlencode`, access_token printed.
- `with-scope` — 4 args with `"read write"`, curl args contain `scope=read write` and `--data-urlencode`, access_token printed.
- `empty-scope` — 4 args with `""`, no `scope=` in curl args, access_token printed.
- `whitespace-scope` — 4 args with `"   "`, no `scope=` in curl args, access_token printed.

If any scenario fails, the helper prints the scenario name, the expected vs. actual state, and the captured curl args. Re-read the relevant code path in the script and the relevant assertions in the test, fix, and re-run.

Also run the sibling test to confirm no regression in the related token script:

```bash
bash tests/auth-code-token-test.sh
```

Expected: exits 0. (Sanity check — the two scripts are independent but live in the same test directory.)

### Step 5: Commit the changes

```bash
git add -f general/bin/client-credentials-token tests/client-credentials-token-test.sh
git commit -m "feat(client-credentials-token): accept optional scope argument

Adds a 4th positional [scope] argument. When present and non-empty
after whitespace normalization, the value is sent in the form body
as scope=<value> via curl --data-urlencode (so space-separated
multi-scope values are encoded as '+' per application/x-www-form-urlencoded).
When absent, empty, or whitespace-only, the scope parameter is omitted
entirely, preserving the existing 3-argument behavior.

The shell test is refactored into a run_scenario helper that
exercises four cases: the original 3-arg regression, a non-empty
scope, an explicit empty scope, and a whitespace-only scope."
```
