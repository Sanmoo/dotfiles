# `http` — minimal REST client CLI design

**Date:** 2026-06-18
**Status:** Awaiting user review of written spec
**Scope:** A small Python script that wraps `curl` with ergonomic flags, variable interpolation, and a `{{VAR}}` template language, distributed via the existing `general/bin` stow package.

---

## 1. Problem Statement

When consuming or testing REST APIs, the same long `curl` incantation is rebuilt from scratch each time:

```sh
curl -i -X POST \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  $BASE_URL/smart-conditions \
  --data @./payload.jsonc
```

Manually composing this every time is error-prone, painful to quote in shell, and offers no place to interpolate values into the payload before sending.

A small CLI should:

- Take the HTTP method as a subcommand (`http post …`, `http get …`).
- Accept the same ergonomic flags you'd otherwise repeat (`-B`, `-t`, `-H`, `-q`, `-f`, `-i`, `-k`, `-L`).
- Allow defining values once and substituting them as `{{NAME}}` anywhere in the constructed request (path, query, headers, file body).
- Execute the resulting `curl` by default; print it on `--dry-run`.
- Live alongside the other dotfiles scripts and be stowed into `~/bin` automatically.

---

## 2. Goals and Non-Goals

### Goals

- One short script (`general/bin/http`, Python stdlib only, shebang) that builds and runs a `curl` command.
- Subcommand-based dispatch: `get`, `post`, `put`, `patch`, `delete`.
- Variable interpolation: `{{NAME}}` markers, applied to the full constructed request, with strict validation (no silent pass-through of undefined variables).
- Template variable source: `-v "K=V"` (repeatable). Environment variables are **not** a template source — they only affect base URL resolution.
- Base URL resolution with predictable precedence.
- Default behavior executes `curl`; `--dry-run` / `-n` prints a copy-pasteable command.
- Reasonable defaults (e.g. auto `Content-Type` for JSON file payloads) without hiding behavior.
- Trivial to write partial shell aliases on top: `alias post='http post -H "Content-Type: application/json"'`.

### Non-Goals

- No config file (no `.httprc`, no `~/.config/http/…`); environment variables and shell aliases cover the use cases.
- No HTTP methods beyond the five listed.
- No multipart form uploads (`-F`), no `--data-raw`/`--data-binary` distinction; only `--data` from `-f <file>` or `-d <string>`.
- No JSON response highlighting, no history, no retry/backoff.
- No integration with OpenAPI, Postman, or Insomnia.
- No tests that require network access; all tests are unit tests over `build_curl_args` and `apply_template`.

---

## 3. Command Surface

### Invocation

```
http <method> [flags] <path>
```

Methods: `get`, `post`, `put`, `patch`, `delete`. The method is a positional subcommand, not a flag — this is what makes the `alias post='http post …'` trick possible.

### Flag Reference

| Flag | Short | Description |
| --- | --- | --- |
| `--base-url URL` | `-B` | Base URL; takes precedence over env vars |
| `--token TOKEN` | `-t` | Shortcut for `-H "Authorization: Bearer TOKEN"`; errors if empty. If both `-t` and an explicit `-H "Authorization: …"` are given, the explicit `-H` wins (last one in argv order is passed to curl). |
| `--header "K: V"` | `-H` | Generic header (repeatable); same syntax as curl |
| `--query "k=v"` | `-q` | Query parameter (repeatable); value is URL-encoded |
| `--file PATH` | `-f` | Body from file; becomes `--data @<PATH>`. Mutually exclusive with `-d`; passing both is an error. |
| `--data STRING` | `-d` | Body from inline string; becomes `--data <STRING>`. Mutually exclusive with `-f`. |
| `--var "K=V"` | `-v` | Template variable (repeatable); substitutes `{{K}}` → `V` |
| `--include` | `-i` | Passes `-i` to curl (show response headers) |
| `--dry-run` | `-n` | Print the curl command; do not execute |
| `--insecure` | `-k` | Passes `-k` to curl (skip TLS verify) |
| `--follow` | `-L` | Passes `-L` to curl (follow redirects) |
| `--help` | `-h` | Usage info (works at top level and per subcommand) |

Flag position is flexible: `-B` may come before or after the path. Standard argparse behavior.

### Base URL Resolution

Precedence (highest first):

1. `-B` flag
2. `HTTP_BASE_URL` environment variable
3. `BASE_URL` environment variable
4. Error: `error: no base URL provided (use -B or set HTTP_BASE_URL)` with exit code 2

### Method → HTTP Verb

| Subcommand | Curl `-X` |
| --- | --- |
| `get` | *(not set; curl default)* |
| `delete` | `-X DELETE` |
| `post` | `-X POST` |
| `put` | `-X PUT` |
| `patch` | `-X PATCH` |

### Required Arguments

- The HTTP method subcommand is required.
- The `<path>` is required. argparse exits 2 if missing.
- Exactly one of `-B`, `HTTP_BASE_URL`, or `BASE_URL` must resolve to a non-empty string (see Base URL Resolution below).

### Auto Content-Type for `-f`

When `-f` is used and the user has not passed any header whose name (case-insensitive) starts with `Content-Type` via `-H`:

| File extension | Header added |
| --- | --- |
| `.json`, `.jsonc` | `Content-Type: application/json` |
| `.xml` | `Content-Type: application/xml` |
| *(other)* | `Content-Type: application/octet-stream` |

With `-d` (inline body) no `Content-Type` is added by default.

### URL Assembly

Final URL is `<BASE_URL>/<PATH>` with a single `/` between them: duplicate slashes are collapsed.

Query params from `-q` are appended as `?k1=v1&k2=v2`. Each value is URL-encoded via `urllib.parse.quote_plus`.

---

## 4. Template Language

### Markers

`{{NAME}}` — Mustache-style. Case-sensitive. The marker text is exactly the variable name between the braces; surrounding whitespace is part of the name and an error (use `{{NAME}}` not `{{ NAME }}`).

### Application Order

After all flag values are collected and read from disk, a single template pass replaces `{{K}}` with the corresponding `V` everywhere: file body (loaded into memory before being passed to curl), path, query values, header values, `-t` value, `-d` value.

This pass is done on the final constructed list of curl arguments, not on a textual template, so quote boundaries and HTTP semantics are preserved.

### Validation

- `{{K}}` for an undefined `K` is a hard error: `error: undefined variable in template: {{K}}`, exit 2.
- `-v "K="` is allowed and produces the empty string.
- A defined variable may legitimately contain `{{` in its replacement value; replacements are not re-expanded.

### Built-in Variables

None in v1. A future revision could expose `{{TIMESTAMP}}` or `{{UUID}}`, but YAGNI.

---

## 5. Output Behavior

### Default (no flag)

Run the curl command via `subprocess.run(["curl", *args])` with no shell, so quoting is unambiguous. Exit code is curl's exit code.

### `--dry-run` / `-n`

Print a single line containing the curl command with values quoted using `shlex.quote` so it is copy-pasteable. Do not execute curl. Exit 0.

### Errors from the tool itself

| Condition | Message (stderr) | Exit |
| --- | --- | --- |
| Invalid method | argparse usage | 2 |
| Undefined variable | `error: undefined variable in template: {{K}}` | 2 |
| File not found (`-f`) | `error: file not found: <path>` | 2 |
| Empty `-t` | `error: --token is empty` | 2 |
| No base URL | `error: no base URL provided (use -B or set HTTP_BASE_URL)` | 2 |
| Curl failure | (curl's own stderr) | curl's exit code |

---

## 6. Architecture

### File Layout

```
general/bin/http          # the script, shebang, stdlib only
tests/http-test.sh        # shell test that stubs curl, matches repo style
```

`general` is already a stow package, so `stow general` places `http` at `~/bin/http` (already on `$PATH` via `.zshrc`).

The test follows the same pattern as `tests/client-credentials-token-test.sh`: create a `tmpdir`, drop a stub `curl` shell script on `PATH` that records its arguments, run `general/bin/http`, then `grep` the recorded args for the expected flags. No pytest, no network.

### Module Structure (single file)

- `parse_args(argv)` — argparse wiring; returns a namespace with all flags and a list of `vars` (parsed into a `dict`).
- `apply_template(text, variables)` — pure function: returns `text` with `{{K}}` replaced; raises on undefined.
- `build_curl_args(args, variables)` — given parsed args and the variables dict, returns a `list[str]` ready to be passed to `subprocess.run(["curl", …])`. This is the unit-testable core.
- `format_curl_command(curl_args)` — joins the list into a single shell-safe line for `--dry-run`.
- `main()` — orchestrates: parse → build → either `print(format_curl_command(...))` or `subprocess.run(["curl", *args])`.

Each function is small and individually testable. `build_curl_args` is the heart of the tool; it is the only function with non-trivial logic.

### Dependencies

Python 3 stdlib only. No `requirements.txt`, no `pyproject.toml`.

---

## 7. Examples

### 1. Post with payload and inline variable

```sh
http post -i -t $AUTH_TOKEN -B $BASE_URL \
  -v "CUSTOMER=019d49fd-2d18-78fc-ab83-f522931f94d9" \
  -f ./payload.jsonc smart-conditions
```

Builds and runs:

```sh
curl -i -X POST \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  $BASE_URL/smart-conditions \
  --data @./payload.jsonc
```

### 2. Get with path templating and query params

```sh
http get -i -t $T -B $B -q "status=active" -q "page=2" \
  -v "ID=42" smart-conditions/{{ID}}
```

Builds: `… $B/smart-conditions/42?status=active&page=2`.

### 3. Delete with inline body

```sh
http delete -i -t $T -B $B -d '{"reason":"obsolete"}' items/99
```

### 4. Dry-run to inspect

```sh
http post -t $T -B $B -f payload.json smart-conditions -n
# prints: curl -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" $B/smart-conditions --data @payload.json
```

### 5. Partial shell aliases

In `.zshrc` (or a stowed aliases file):

```sh
alias post='http post -H "Content-Type: application/json"'
alias auth='http -H "Authorization: Bearer $AUTH_TOKEN" -H "Accept: application/json"'
```

Then `post smart-conditions -f payload.json` works.

---

## 8. Validation Plan

### Static

- `python3 -m py_compile general/bin/http` — script parses.
- `python3 -c "import ast; ast.parse(open('general/bin/http').read())"` — same, no compile needed for shebang scripts.
- `shellcheck general/bin/http` if available — though this is Python, not bash.

### Unit tests (`tests/http-test.sh`)

A single shell test script that stubs `curl` and asserts on what the tool would have called. Cases, in order:

1. `apply_template` — exercised via an end-to-end call: `http post -B x -v "K=v" -d 'a={{K}}b' foo` writes `--data a=vb` to the stub's log.
2. `apply_template` raises on undefined variable — calling `http post -B x -d 'a={{X}}' foo` exits non-zero and prints the error message to stderr.
3. `build_curl_args` adds `Content-Type: application/json` for `.json` and `.jsonc` files when no `-H` is given.
4. `build_curl_args` does **not** override an explicit `-H "Content-Type: …"`.
5. `build_curl_args` resolves base URL in the documented precedence (`-B` > `HTTP_BASE_URL` > `BASE_URL`); unset env vars and no `-B` exits 2.
6. `build_curl_args` collapses duplicate slashes between base URL and path.
7. `build_curl_args` URL-encodes query values.
8. `build_curl_args` includes `-X POST` for `post`, omits `-X` for `get`, includes `-X DELETE` for `delete`, etc.
9. `build_curl_args` expands `-t` into the `Authorization: Bearer …` header.
10. `build_curl_args` lets multiple `-H` flags stack.
11. `format_curl_command` (dry-run) prints a single line that round-trips through `shlex.split` and matches the would-be curl invocation.
12. `-f` and `-d` together is an error.
13. Missing path is an error.

No test performs network I/O. The stub `curl` only records argv to a log file and exits 0.

### Manual

- `http --help` shows usage.
- `http post --help` shows post-specific usage.
- `http post -t '' -B x` exits 2 with the empty-token error.
- `http post smart-conditions` (no base URL) exits 2 with the resolution error.
- `http post -t $T -B $B -n smart-conditions` prints a curl line that, when copied and run, behaves identically to running the tool without `-n`.
- An end-to-end test against a known local server (e.g. `http-server` or a tiny `python3 -m http.server` mock) for one GET and one POST.

---

## 9. Success Criteria

The feature is successful when:

- `general/bin/http` exists, is executable, and lives at `~/bin/http` after `stow general`.
- `http <method> [flags] <path>` runs curl with the expected headers, body, and URL.
- `{{VAR}}` substitution works in path, query, header values, file body, inline body, and the `-t` value, with a hard error on undefined variables.
- `-B`, `HTTP_BASE_URL`, and `BASE_URL` resolve base URL in the documented precedence.
- `-n` prints a copy-pasteable curl line; default runs it.
- All test cases in `tests/http-test.sh` pass when run with `bash tests/http-test.sh`.
- A roundtrip manual test against a local mock server produces the expected HTTP request.

---

## 10. Chosen Approach Summary

A single-file Python 3 script in `general/bin/http`, stdlib only, that builds a list of `curl` arguments in a pure function and then either prints or executes them. Variable interpolation uses `{{NAME}}` markers with strict undefined-variable validation. The HTTP method is a subcommand so users can write partial shell aliases on top. The tool is intentionally small: no config file, no extra HTTP methods, no multipart, no network-aware tests.
