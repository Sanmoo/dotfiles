# Optional OpenCollection Query Parameters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-invocation support for omitting selected or all OpenCollection query parameters when their template variables are not explicitly supplied or are left empty.

**Architecture:** Keep the existing single-file Python CLI structure. Normalize the new argparse option into an all-or-named selection, analyze optional queries before ordinary missing-variable resolution, pass disabled query identities into curl argument construction, and record the effective selection in the equivalent command.

**Tech Stack:** Python 3 standard library (`argparse`, `dataclasses` are not required), PyYAML, Bash integration tests, `curl` stubs.

## Global Constraints

- Preserve behavior when `--dqwnp` is absent and the interactive opt-in is declined.
- A bare `--dqwnp` covers all YAML query parameters; named values require `=`: `--dqwnp=page,limit`.
- `--disable-query-when-not-provided` and `--dqwnp` are aliases and may be repeated.
- Only non-empty `-v/--var` values initially enable a covered query; inherited defaults do not.
- In interactive mode, absent covered-query variables use `value for NAME (leave empty to disable):`.
- Any empty required value disables the complete covered query.
- Variables still used outside an omitted query remain required.
- YAML `disabled: true`, CLI-added `-q`, authentication, headers, path parameters, and bodies retain current semantics.
- Do not modify unrelated existing changes in `git/.gitignore_global` or `pi-mac/.pi/agent/settings.json`.

---

## File Structure

- Modify `general/bin/http`: parse and normalize the option, validate query names, resolve optional-query variables, omit disabled queries, prompt for interactive activation, and render the equivalent command.
- Modify `tests/http-oc-test.sh`: add parser-level, non-interactive integration, variable-sharing, interactive, and equivalent-command regression coverage.

No new runtime modules or dependencies are needed. The existing script is intentionally monolithic, so this focused feature should follow that structure rather than introduce an unrelated split.

### Task 1: Parse and Validate the Query Selection

**Files:**

- Modify: `general/bin/http:132-177`
- Modify: `general/bin/http:506-522`
- Test: `tests/http-oc-test.sh` after Test 27

**Interfaces:**

- Consumes: raw argparse occurrences from `args.disable_queries_when_not_provided`.
- Produces: `parse_optional_query_selection(raw_values) -> tuple[bool, set[str]]`, where the boolean means “feature requested” and an empty set means “all queries”; `get_request_query_params(request_doc) -> list[dict]`; `validate_optional_query_selection(request_doc, requested, names) -> None`.

- [ ] **Step 1: Add failing parser and validation tests**

Append an embedded Python test to `tests/http-oc-test.sh`:

```bash
# ---------- Test 28: dqwnp parser and validation ----------
echo "test 28: dqwnp parser and validation"
python3 <<'PYEOF'
import importlib.machinery

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
```

- [ ] **Step 2: Run the new test and verify it fails**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: existing Tests 1–27 pass, then Test 28 fails because argparse does not recognize `--dqwnp`.

- [ ] **Step 3: Add unambiguous bare-option preprocessing and the argparse alias**

An argparse option with `nargs="?"` would consume a following positional request name in `http oc --dqwnp get-users`. Avoid that ambiguity by rewriting an exact bare option token to a private sentinel before parsing, while leaving `--dqwnp=page` unchanged:

```python
OC_ALL_QUERIES_SENTINEL = "__HTTP_OC_ALL_QUERIES__"
OC_OPTIONAL_QUERY_FLAGS = (
    "--disable-query-when-not-provided",
    "--dqwnp",
)


def normalize_oc_optional_query_argv(argv):
    return [
        f"{token}={OC_ALL_QUERIES_SENTINEL}"
        if token in OC_OPTIONAL_QUERY_FLAGS else token
        for token in argv
    ]
```

In `make_oc_parser`, add an append option that always receives either the sentinel or an explicit `=` value:

```python
p.add_argument(
    *OC_OPTIONAL_QUERY_FLAGS,
    dest="disable_queries_when_not_provided",
    action="append",
    metavar="QUERY[,QUERY...]",
    help=(
        "omit selected query parameters when their variables are not "
        "explicitly provided; omit QUERY to apply to all queries"
    ),
)
```

In the `oc` branch of `parse_args`, parse the normalized tail:

```python
args = make_oc_parser().parse_args(normalize_oc_optional_query_argv(argv[1:]))
```

This supports a bare option before or after the request positional. Named space-separated values are intentionally unsupported; names must use `=`.

- [ ] **Step 4: Implement normalization and request-query helpers**

Add these functions near `find_template_variables`:

```python
def parse_optional_query_selection(raw_values):
    if raw_values is None:
        return False, set()
    names = set()
    for raw in raw_values:
        if raw == OC_ALL_QUERIES_SENTINEL:
            return True, set()
        names.update(name for name in raw.split(",") if name)
    return True, names


def get_request_params(request_doc):
    request = request_doc.get("request") if isinstance(request_doc.get("request"), dict) else {}
    return [param for param in request.get("params") or [] if isinstance(param, dict)]


def get_request_query_params(request_doc):
    return [
        param for param in get_request_params(request_doc)
        if param.get("disabled") is not True
        and param.get("type", "query") == "query"
    ]


def validate_optional_query_selection(request_doc, requested, names):
    if not requested or not names:
        return
    params = get_request_params(request_doc)
    query_names = {
        str(param.get("name")) for param in get_request_query_params(request_doc)
        if param.get("name") is not None
    }
    all_names = {
        str(param.get("name")) for param in params
        if param.get("name") is not None
    }
    for name in sorted(names):
        if name in query_names:
            continue
        if name in all_names:
            die("parameter is not a query parameter: " + name)
        available = ", ".join(sorted(query_names)) or "(none)"
        die(f"query parameter not found: {name}; available: {available}")
```

- [ ] **Step 5: Run the parser test and inspect the errors manually**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: all 28 tests pass; the two intentional validation failures print the specified errors to stderr without tracebacks.

- [ ] **Step 6: Commit Task 1**

```bash
git add general/bin/http tests/http-oc-test.sh
git commit -m "feat(http): parse optional oc query selection"
```

### Task 2: Resolve and Omit Optional Queries Non-Interactively

**Files:**

- Modify: `general/bin/http:506-579`
- Modify: `general/bin/http:790-833`
- Modify: `general/bin/http:857-890`
- Test: `tests/http-oc-test.sh` after Test 28

**Interfaces:**

- Consumes: `cli_vars: dict[str, str]`, normalized `(requested, names)`, request YAML, and `interactive`.
- Produces: `resolve_optional_queries(request_doc, cli_vars, variables, requested, names, interactive) -> tuple[dict[str, str], dict[str, str], set[int]]`; the integer set contains zero-based `request.params` indexes to omit, avoiding accidental omission of unrelated duplicate objects.
- Updates: `resolve_oc_variables(...) -> tuple[dict, dict, set[int]]`; `build_basic_oc_args(..., disabled_query_indexes=None)`.

- [ ] **Step 1: Add failing non-interactive integration tests**

Append fixtures that define `page`, `limit`, a literal query, duplicate `filter` entries, and an unselected mandatory query:

```bash
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
[ "$OC_EXIT" -eq 2 ] || { echo "FAIL: expected exit 2" >&2; exit 1; }
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
```

- [ ] **Step 2: Run Tests 29–31 and verify failure**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: Test 29 fails because optional queries are still included or reported as missing.

- [ ] **Step 3: Implement covered-query selection and analysis**

Add helpers near the variable-resolution functions:

```python
def optional_query_is_covered(param, requested, names):
    if not requested:
        return False
    if not names:
        return True
    name = param.get("name")
    return name is not None and str(name) in names


def resolve_optional_queries(request_doc, cli_vars, variables, requested, names, interactive):
    prompted = {}
    disabled_indexes = set()
    params = get_request_params(request_doc)
    prompt_cache = {}
    for index, param in enumerate(params):
        if param.get("disabled") is True or param.get("type", "query") != "query":
            continue
        if not optional_query_is_covered(param, requested, names):
            continue
        needed = find_template_variables(param.get("name", ""))
        needed.update(find_template_variables(param.get("value", "")))
        if not needed:
            continue
        disable = False
        for variable_name in sorted(needed):
            if variable_name in cli_vars:
                value = cli_vars[variable_name]
            elif interactive:
                if variable_name not in prompt_cache:
                    prompt_cache[variable_name] = input(
                        f"value for {variable_name} (leave empty to disable): "
                    )
                value = prompt_cache[variable_name]
                prompted[variable_name] = value
            else:
                value = ""
            if value == "":
                disable = True
            else:
                variables[variable_name] = value
        if disable:
            disabled_indexes.add(index)
    return variables, prompted, disabled_indexes
```

After analysis, expand `disabled_indexes` to every duplicate covered query whose template variables resolve empty. Keep indexes as the construction contract, while named selection naturally covers duplicate names.

- [ ] **Step 4: Exclude disabled-query-only variables from ordinary preflight**

Refactor `collect_missing_variables` to accept `disabled_query_indexes=None`. Iterate `get_request_params(request_doc)` with `enumerate`, skipping an index only for query-variable collection; continue collecting URL, enabled headers, supported body, path variables, and every non-disabled query. Preserve `found.difference_update(path_param_names)`.

Update `resolve_oc_variables` to:

```python
def resolve_oc_variables(
    collection, request, environment, cli_vars, interactive,
    optional_queries_requested=False, optional_query_names=None,
):
    variables = {}
    variables.update(get_collection_variables(collection["manifest"]))
    variables.update(get_request_variables(request["data"]))
    if environment:
        variables.update(variables_list_to_dict(environment.get("variables")))
    variables.update(cli_vars)
    variables, optional_prompted, disabled_indexes = resolve_optional_queries(
        request["data"], cli_vars, variables,
        optional_queries_requested, optional_query_names or set(), interactive,
    )
    missing = collect_missing_variables(request["data"], variables, disabled_indexes)
    prompted = dict(optional_prompted)
    if missing:
        if interactive:
            required_prompted = prompt_missing_variables(missing)
            prompted.update(required_prompted)
            variables.update(required_prompted)
        else:
            die("missing variables: " + ", ".join(sorted(missing)))
    return variables, prompted, disabled_indexes
```

This ordering ensures a shared variable omitted from an optional query remains missing when URL/header/body/path or a mandatory query still uses it.

- [ ] **Step 5: Omit query indexes during request construction**

Change the signature and query loop:

```python
def build_basic_oc_args(args, request_doc, variables, disabled_query_indexes=None):
    disabled_query_indexes = disabled_query_indexes or set()
    # existing setup remains
    queries = []
    for index, param in enumerate(request.get("params") or []):
        if index in disabled_query_indexes:
            continue
        # retain existing disabled/type/name/template logic
```

In `main_oc`, normalize and validate immediately after selecting the request, pass the selection into `resolve_oc_variables`, and pass returned indexes into `build_basic_oc_args`.

- [ ] **Step 6: Add and pass the shared-variable regression test**

Append:

```bash
# ---------- Test 32: omitted query does not hide shared requirements ----------
echo "test 32: shared optional-query variable remains required elsewhere"
cat >"$OC_ROOT/collectionA/requests/shared.yaml" <<'YAML'
type: http
request:
  method: GET
  url: https://api.example.com/{{shared}}
  params:
    - name: optional
      type: query
      value: "{{shared}}"
YAML
run_http_oc_expect_fail --no-interactive -c collectionA -n --dqwnp shared
[ "$OC_EXIT" -eq 2 ] || { echo "FAIL: expected exit 2" >&2; exit 1; }
assert_contains "$OC_STDERR" "shared" "URL must keep the shared variable required"
```

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: all 32 tests pass and the script ends with `OK`.

- [ ] **Step 7: Commit Task 2**

```bash
git add general/bin/http tests/http-oc-test.sh
git commit -m "feat(http): omit unprovided oc query parameters"
```

### Task 3: Add Interactive Activation and Reproducible Commands

**Files:**

- Modify: `general/bin/http:552-579`
- Modify: `general/bin/http:835-900`
- Test: `tests/http-oc-test.sh` after Test 32

**Interfaces:**

- Consumes: whether the CLI option was present, request query list, TTY-derived `interactive`.
- Produces: `prompt_enable_optional_queries() -> bool`; expanded `build_equivalent_command(..., optional_queries_requested=False, optional_query_names=None)`.

- [ ] **Step 1: Add failing deterministic interactive unit tests**

Append an embedded Python test using patched `input`, avoiding platform-dependent PTY behavior:

```bash
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

cmd = http.build_equivalent_command(
    "collectionA", "development", "search", {}, True, set(),
)
assert "--dqwnp" in cmd
PYEOF
```

- [ ] **Step 2: Run Test 33 and verify failure**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: Test 33 fails because `prompt_enable_optional_queries` and the expanded equivalent-command signature do not exist.

- [ ] **Step 3: Implement the activation prompt**

Add:

```python
def prompt_enable_optional_queries():
    global OC_INTERACTIVE_USED
    OC_INTERACTIVE_USED = True
    answer = input(
        "Allow disabling query parameters with an empty value? [y/N] "
    ).strip().lower()
    return answer in ("y", "yes")
```

In `main_oc`, after request/environment selection and CLI option normalization:

```python
query_params = get_request_query_params(request["data"])
if interactive and query_params and not optional_queries_requested:
    if prompt_enable_optional_queries():
        optional_queries_requested = True
        optional_query_names = set()
```

Do not ask when no query exists, when non-interactive, or when either named or global CLI selection was supplied.

- [ ] **Step 4: Expand equivalent-command rendering**

Change the signature:

```python
def build_equivalent_command(
    collection_name, env_name, request_name, cli_vars=None,
    optional_queries_requested=False, optional_query_names=None,
):
```

Before appending `request_name`, add:

```python
if optional_queries_requested:
    if optional_query_names:
        names = ",".join(sorted(optional_query_names))
        cmd.append(f"--dqwnp={names}")
    else:
        cmd.append("--dqwnp")
```

Thread both selection values through `print_oc_summary`, the early `equivalent_cmd` in `main_oc`, and its `finally` fallback. Keep effective non-empty prompted values in `-v`; filter empty optional prompted values before calling `build_equivalent_command`:

```python
effective_vars = {
    key: value for key, value in {**cli_vars, **prompted}.items()
    if value != ""
}
```

- [ ] **Step 5: Add decline, no-query, and named-command tests**

Extend the embedded test:

```python
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
```

Add a non-interactive no-query integration assertion to ensure `http oc` without the option still follows existing behavior. Retain existing Test 23 and Test 26 expectations unchanged for requests without query parameters; this verifies no unsolicited activation prompt or equivalent flag.

- [ ] **Step 6: Run focused syntax and LSP checks before the full suite**

Run:

```bash
python3 -m py_compile general/bin/http
```

Expected: exit 0 with no output.

Run LSP diagnostics on `general/bin/http` and `tests/http-oc-test.sh`. Expected: no new errors.

- [ ] **Step 7: Run the complete regression suites**

Run:

```bash
bash tests/http-oc-test.sh
bash tests/http-test.sh
```

Expected: both scripts exit 0 and end with `OK`.

- [ ] **Step 8: Check session diagnostics and diff hygiene**

Run `lens_diagnostics` with `mode=all` for the edited files. Expected: no blocking errors.

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only `general/bin/http` and `tests/http-oc-test.sh` are staged for this task, while the user's unrelated pre-existing modified files remain untouched.

- [ ] **Step 9: Commit Task 3**

```bash
git add general/bin/http tests/http-oc-test.sh
git commit -m "feat(http): prompt for optional oc queries"
```

- [ ] **Step 10: Verify the committed result**

Run:

```bash
bash tests/http-oc-test.sh && bash tests/http-test.sh
git log -3 --oneline
git status --short
```

Expected: both suites pass; the three implementation commits are present; only unrelated pre-existing working-tree changes, if any, remain.
