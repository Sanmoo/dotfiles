# `client-credentials-token` — optional `scope` argument design

**Date:** 2026-06-29
**Status:** Awaiting user review of written spec
**Scope:** Extend `general/bin/client-credentials-token` to accept an optional `scope` argument that is sent in the OAuth2 token request form body when provided.

---

## 1. Problem Statement

`general/bin/client-credentials-token` currently performs a standard OAuth 2.0 Client Credentials grant with three required positional arguments: `client_id`, `client_secret`, and `token_url`. It posts a form body containing `grant_type`, `client_id`, and `client_secret`, and prints the resulting `access_token` to stdout.

Some authorization servers and clients require the caller to request specific scopes; some default to all allowed scopes; some reject the request if the requested scope is invalid. The script currently has no way to influence the scope that the server returns, forcing callers to fall back to manual `curl` invocations for any non-trivial flow.

---

## 2. Goals and Non-Goals

### Goals

- Add an optional 4th positional argument that carries the requested scope.
- Preserve full backward compatibility with the current 3-argument invocation.
- Send the `scope` parameter in the form body only when the caller provided a non-empty, non-whitespace value.
- URL-encode the scope value correctly so that space-separated multi-scope values (the OAuth2 default format) are transmitted as `scope=read+write` rather than as a literal space.
- Keep the change minimal and local to the script; no new dependencies.

### Non-Goals

- No new CLI flags, subcommands, or argparse-style option parsing.
- No validation of scope values against any server-known catalog.
- No change to the token extraction, error handling, or output format.
- No support for alternative encodings (e.g. comma-separated scopes) — OAuth2 RFC 6749 §3.3 specifies space-separated.
- No interactive scope selection or multi-tenant scope resolution.

---

## 3. Command Surface

### Updated usage

```sh
client-credentials-token <client_id> <client_secret> <token_url> [scope]
```

### Examples

```sh
# 3-arg form: unchanged behavior, no `scope` sent
client-credentials-token my-client my-secret https://auth.example/token

# 4-arg form with a single scope
client-credentials-token my-client my-secret https://auth.example/token read

# 4-arg form with multiple space-separated scopes
client-credentials-token my-client my-secret https://auth.example/token "read write admin"
```

### Argument counts

- Exactly 3 args → existing behavior; `scope` is not sent.
- Exactly 4 args → `scope` is sent only if the 4th argument is non-empty after whitespace normalization.
- Any other count → usage message on stderr, exit 1.

---

## 4. Chosen Approach

Keep the script’s positional argument style and add a single optional 4th argument. Internally, build the `curl` command line as a bash array so the scope flag can be appended conditionally, and use `curl --data-urlencode` for the scope so that spaces and other reserved characters are encoded per `application/x-www-form-urlencoded`.

### Why this approach

- It preserves the script’s existing CLI shape (no flag parser, no `getopts`).
- It fixes the one place where the current `-d` form would mis-encode a value with a space (the OAuth2 multi-scope separator) without touching the working args (`grant_type`, `client_id`, `client_secret`).
- The array-based curl invocation leaves a clear hook for any future optional form parameters.

### Alternatives considered

1. **Add a `--scope` flag (consistent with `auth-code-token`)** — Would require a small flag parser in a script that currently has none. Inconsistent with the script’s existing minimal style.
2. **Use `-d "scope=$SCOPE"` for parity with the other form fields** — `curl -d` does not URL-encode, so a value like `read write` would be transmitted as a literal space, which most form parsers handle inconsistently. Fragile for the most common multi-scope case.
3. **Use `--data-urlencode` for every form field** — More consistent, but is a wider refactor than the stated goal and changes behavior for fields that currently work.

---

## 5. Scope Handling Semantics

### Argument parsing

```sh
SCOPE="${4:-}"

# Whitespace-only scope is treated as "no scope"
if [ -z "${SCOPE// /}" ]; then
  SCOPE=""
fi
```

- `${4:-}` defaults to the empty string when the 4th argument is absent, avoiding `set -u` failures.
- The `${SCOPE// /}` expansion strips every space; an empty result after that means the original value was empty or consisted solely of spaces.

### curl invocation

```sh
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
```

- Existing fields keep their `-d` form because they have no encoding-sensitive characters in normal use.
- The scope field uses `--data-urlencode` so that `read write` becomes `read+write` in the wire format, matching what OAuth2 form parsers expect.

---

## 6. Error Handling

No new error paths are introduced. Existing behavior is preserved:

| Condition | Behavior |
| --- | --- |
| `curl` returns non-2xx | `--fail` makes curl exit non-zero; `set -e` aborts the script with curl’s error on stderr. |
| Response body has no `access_token` | Error on stderr, exit 1. |
| Argument count is not 3 or 4 | Updated `Usage:` line on stderr, exit 1. |
| `curl` or `jq` not installed | Error on stderr naming the missing command, exit 1 (unchanged). |

The whitespace-normalized empty scope is **not** an error — it is equivalent to omitting the argument.

---

## 7. Testing Strategy

Extend `tests/client-credentials-token-test.sh` using its existing `curl` stub pattern. The stub already writes its arguments to a file, so the new tests can assert on that file the same way the existing assertions do.

### New assertions

1. **3 args, no scope**
   - The captured curl args do **not** contain `scope=`.
   - The captured curl args do **not** contain `--data-urlencode`.
2. **4 args with a non-empty scope**
   - The captured curl args contain `--data-urlencode scope=<value>` for the value provided.
3. **4 args with a whitespace-only scope** (`"   "`)
   - The captured curl args do **not** contain `scope=`.

### Existing assertions

All existing assertions in `tests/client-credentials-token-test.sh` continue to hold because the 3-argument path is unchanged. The existing test file does not currently assert on the `Usage:` line, so no existing assertion needs to be edited; the new usage text is verified by the negative test path (calling the script with the wrong number of arguments and observing non-zero exit).

### Test level

Pure shell-level tests with a stubbed `curl`. No network, no real authorization server. This matches the existing test design and keeps the suite deterministic.

---

## 8. Implementation Shape

### Files to change

- `general/bin/client-credentials-token` — the script itself.
- `tests/client-credentials-token-test.sh` — add scope-related assertions and update the `Usage:` assertion.

### Code changes in the script (conceptual)

1. Loosen the argument-count check from strict `3` to `3` or `4`.
2. Update the heredoc `Usage:` text to include `[scope]`.
3. Read the optional 4th argument into `SCOPE` with `${4:-}`.
4. Normalize whitespace-only to empty.
5. Move the `curl` arguments into a bash array.
6. Conditionally append `--data-urlencode "scope=$SCOPE"` to the array.
7. Invoke `curl "${CURL_ARGS[@]}"` instead of the long literal command line.

No other code paths change. The token extraction, the `jq` dependency check, and the `printf '%s\n' "$token"` output all remain untouched.

---

## 9. Success Criteria

The work is successful when:

- `client-credentials-token` accepts 3 or 4 positional arguments; any other count exits non-zero with a usage message.
- With 3 arguments, the curl invocation does not include any `scope` parameter and the response handling is unchanged.
- With 4 arguments where the 4th is a non-empty, non-whitespace value, the curl invocation includes `--data-urlencode scope=<value>`.
- With 4 arguments where the 4th is empty or whitespace-only, the curl invocation does not include any `scope` parameter.
- A multi-scope value such as `read write` is transmitted as `read+write` in the form body, matching OAuth2 form encoding.
- `tests/client-credentials-token-test.sh` covers the three new behavior branches and continues to pass.
- The existing test suite continues to pass without modification to the original 3-argument assertions (other than the usage text update).
