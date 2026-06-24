# `http get` default Content-Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `http get` send `Content-Type: application/json` by default when no explicit `Content-Type` header is provided, while preserving explicit-header precedence and existing `-f` inference.

**Architecture:** Keep the change inside the existing single-file Python CLI. Add one small helper that resolves the auto `Content-Type` in priority order: explicit header suppression first, then `-f` file-extension inference, then the GET default. The shell test remains the only test harness and continues to stub `curl` so the change stays deterministic and local.

**Tech Stack:** Python 3 stdlib only (`argparse`, `os`, `pathlib`, `shlex`, `subprocess`, `sys`, `urllib.parse`), bash, `curl` stubbed in shell tests.

## File Structure

| File | Responsibility |
| --- | --- |
| `general/bin/http` | Add `resolve_auto_content_type`/`has_header` helpers and emit at most one auto `Content-Type` header. |
| `tests/http-test.sh` | Add regression tests for GET default `Content-Type`, explicit-header suppression, and `-f` precedence. |

No other files are created or modified.

## Global Constraints

- Python 3 stdlib only.
- No new flags.
- No change to base URL resolution.
- No change to `POST` / `PUT` / `PATCH` / `DELETE` behavior beyond the shared Content-Type resolution logic needed to avoid duplicate auto headers.
- No `Accept` header default.
- No config file or environment variable for overriding the new GET default.
- Preserve the current `-f` behavior for file-backed request bodies.
- Keep the change small and localized to `general/bin/http` and its shell tests.
- Tests continue to stub `curl`; no network I/O.

---

### Task 1: Add regression tests for GET Content-Type precedence

**Files:**

- Modify: `tests/http-test.sh`

**Interfaces:**

- Consumes existing helpers already in the file: `run_http`, `assert_contains`, `assert_not_contains`, `run_http_expect_fail`.
- Produces new shell regression cases that define the desired GET default, explicit-header suppression, and `-f` precedence.

- [ ] **Step 1: Append the new regression cases before the final `echo "OK"`**

Add this block to `tests/http-test.sh` after the current last test case and before `echo "OK"`:

```bash
# ---------- Test 34: GET defaults Content-Type to application/json ----------
echo "test 34: GET defaults Content-Type to application/json"
run_http get -B https://api.example.com foo
grep -Fq -- "Content-Type: application/json" "$HTTP_CURL_ARGS" || {
 echo "FAIL: GET should default to application/json" >&2
 cat "$HTTP_CURL_ARGS" >&2
 exit 1
}
count="$(grep -Fc -- 'Content-Type:' "$HTTP_CURL_ARGS")"
[ "$count" -eq 1 ] || {
 echo "FAIL: GET should emit exactly one Content-Type header" >&2
 cat "$HTTP_CURL_ARGS" >&2
 exit 1
}

# ---------- Test 35: explicit Content-Type wins on GET ----------
echo "test 35: explicit Content-Type wins on GET"
run_http get -B https://api.example.com -H "Content-Type: text/plain" foo
grep -Fq -- "Content-Type: text/plain" "$HTTP_CURL_ARGS" || {
 echo "FAIL: explicit GET Content-Type missing" >&2
 cat "$HTTP_CURL_ARGS" >&2
 exit 1
}
if grep -Fq -- "Content-Type: application/json" "$HTTP_CURL_ARGS"; then
 echo "FAIL: explicit Content-Type should suppress the JSON default" >&2
 cat "$HTTP_CURL_ARGS" >&2
 exit 1
fi
count="$(grep -Fc -- 'Content-Type:' "$HTTP_CURL_ARGS")"
[ "$count" -eq 1 ] || {
 echo "FAIL: GET with explicit Content-Type should emit exactly one Content-Type header" >&2
 cat "$HTTP_CURL_ARGS" >&2
 exit 1
}

# ---------- Test 36: GET with -f keeps file-derived Content-Type ----------
echo "test 36: GET with -f keeps file-derived Content-Type"
PAYLOAD="$HTTP_TMPDIR/payload.xml"
echo '<x/>' >"$PAYLOAD"
run_http get -B https://api.example.com -f "$PAYLOAD" foo
grep -Fq -- "Content-Type: application/xml" "$HTTP_CURL_ARGS" || {
 echo "FAIL: GET + -f should keep application/xml" >&2
 cat "$HTTP_CURL_ARGS" >&2
 exit 1
}
if grep -Fq -- "Content-Type: application/json" "$HTTP_CURL_ARGS"; then
 echo "FAIL: GET default must not override -f Content-Type" >&2
 cat "$HTTP_CURL_ARGS" >&2
 exit 1
fi
count="$(grep -Fc -- 'Content-Type:' "$HTTP_CURL_ARGS")"
[ "$count" -eq 1 ] || {
 echo "FAIL: GET + -f should emit exactly one Content-Type header" >&2
 cat "$HTTP_CURL_ARGS" >&2
 exit 1
}
```

- [ ] **Step 2: Run the shell test suite and verify the new tests fail on the current code**

Run: `bash tests/http-test.sh`

Expected: the suite stops at `test 34: GET defaults Content-Type to application/json` with `FAIL: GET should default to application/json`, because the current implementation does not add the GET default yet.

- [ ] **Step 3: Commit the failing regression tests**

```bash
git add -f tests/http-test.sh
git -c commit.gpgsign=false commit -m "test(http): add GET Content-Type regressions"
```

---

### Task 2: Centralize auto Content-Type resolution in `general/bin/http`

**Files:**

- Modify: `general/bin/http`

**Interfaces:**

- Add `has_header(headers, header_name) -> bool`.
- Add `resolve_auto_content_type(args) -> str | None`.
- Update `build_curl_args(args, base_url, variables=None) -> list[str]` to append a single auto `Content-Type` header when the resolver returns one.
- `resolve_auto_content_type` must keep this priority order: explicit `Content-Type` header suppresses everything, `-f` file inference wins next, GET default comes last.

- [ ] **Step 1: Add the new helpers near the existing request-building code**

Insert these helpers near `build_curl_args` (above it or immediately before it):

```python
def has_header(headers, header_name):
    needle = header_name.lower()
    return any(
        h.split(":", 1)[0].strip().lower() == needle
        for h in headers or []
    )


def resolve_auto_content_type(args):
    if has_header(args.headers, "Content-Type"):
        return None
    if args.file:
        ext = Path(args.file).suffix.lower()
        if ext in (".json", ".jsonc"):
            return "application/json"
        if ext == ".xml":
            return "application/xml"
        return "application/octet-stream"
    if args.method == "get":
        return "application/json"
    return None
```

- [ ] **Step 2: Replace the inline `-f` Content-Type block with one resolver call**

Update `build_curl_args` so it appends exactly one auto header from the resolver instead of the existing inline `-f` branch. The relevant section should look like this:

```python
    for h in args.headers or []:
        out += ["-H", h]
    if args.token:
        out += ["-H", f"Authorization: Bearer {args.token}"]

    auto_content_type = resolve_auto_content_type(args)
    if auto_content_type is not None:
        out += ["-H", f"Content-Type: {auto_content_type}"]

    # Body handling
    body_arg = None
    body_is_file = False
```

Remove the old inline `# Auto Content-Type for -f` block so there is only one decision point for auto `Content-Type`.

- [ ] **Step 3: Run syntax and shell verification**

Run:

```bash
python3 -m py_compile general/bin/http
bash tests/http-test.sh
```

Expected:

- `python3 -m py_compile general/bin/http` exits 0 with no output.
- `bash tests/http-test.sh` prints every test section through the new GET cases and ends with `OK`.

- [ ] **Step 4: Commit the implementation**

```bash
git add -f general/bin/http tests/http-test.sh
git -c commit.gpgsign=false commit -m "feat(http): default GET content-type"
```

---

## Coverage Check

- GET default header: Task 1 test 34, Task 2 resolver branch `args.method == "get"`.
- Explicit `Content-Type` suppression: Task 1 test 35, Task 2 `has_header(...)` early return.
- `-f` precedence: Task 1 test 36, Task 2 resolver checks `args.file` before GET default.
- No base URL / no new flags / no `Accept` header / no config changes: preserved by not touching those code paths.
- Existing non-GET behavior: preserved by only adding a GET fallback after explicit and file-backed Content-Type resolution.
