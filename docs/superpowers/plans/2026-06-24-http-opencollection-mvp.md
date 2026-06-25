# `http oc` OpenCollection MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `http oc` to `general/bin/http` so it can discover OpenCollection-like YAML collections, resolve requests/environments/variables interactively or non-interactively, support OAuth2 MVP token resolution/cache, and execute the resulting request through curl.

**Architecture:** Keep the existing direct `http get/post/...` path intact. Add an `oc` subcommand plus focused helper functions inside `general/bin/http` that load YAML config, discover collections/requests, resolve variables/auth, and translate an OpenCollection request into the existing curl argument builder. Add dedicated shell coverage in `tests/http-oc-test.sh` with fake HOME, fake collections, and stubbed curl/OAuth behavior.

**Tech Stack:** Python 3 stdlib plus PyYAML (`yaml` import), bash tests, existing subprocess dependencies (`curl`, optional `fzf`, existing OAuth helper scripts), no networked tests.

## Global Constraints

- Existing `http get/post/put/patch/delete` behavior must remain covered by `tests/http-test.sh` and must not regress.
- OpenCollection config file path is exactly `~/.config/.httprc`.
- `.httprc` format is YAML with top-level `collections: [paths...]`.
- Collection manifest names, in order: `opencollection.yaml`, `opencollection.yml`, `collection.yaml`, `collection.yml`.
- Request discovery is by YAML basename under the selected collection tree.
- Dedicated OpenCollection tests live in `tests/http-oc-test.sh`.
- Variable precedence is CLI `-v` > selected environment > request variables > collection variables > interactive prompt > non-interactive error.
- `--no-interactive` disables fzf/prompts and turns missing/ambiguous values into errors.
- OAuth2 MVP supports only `client_credentials` and `authorization_code` grant types.
- OAuth token cache directory is `~/.cache/http-oc/`.
- Token cache is reused only when `expires_at` is valid with a 60-second safety margin.
- Other auth modes are not interpreted; users can model them as headers with variables.
- Raw OpenCollection body types supported: `json`, `xml`, `text`, `sparql`.
- No multipart/file body support in OpenCollection mode.
- Tool errors exit 2 and print to stderr; curl failures propagate curl's exit code.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `general/bin/http` | Existing CLI plus new `oc` parser/helpers. Owns YAML loading, discovery, variable resolution, auth/cache, curl translation, and execution. |
| `tests/http-oc-test.sh` | New dedicated bash test suite for OpenCollection mode. Uses fake HOME, generated YAML fixtures, and stub curl/OAuth paths. |
| `tests/http-test.sh` | Existing direct CLI regression suite. Must continue to pass unchanged unless a tiny shared helper adjustment is unavoidable. |
| `docs/superpowers/specs/2026-06-24-http-opencollection-mvp-design.md` | Approved design reference. No implementation changes required. |

The plan keeps implementation in one script to match the current project style. If `general/bin/http` becomes hard to navigate after this MVP, extraction can be a follow-up refactor after tests are green.

---

### Task 1: Add `oc` parser skeleton and dedicated test harness

**Files:**

- Modify: `general/bin/http`
- Create: `tests/http-oc-test.sh`

**Interfaces:**

- Consumes existing: `format_curl_command(curl_args: list[str]) -> str`, `build_curl_args(args, base_url, variables=None) -> list[str]`.
- Produces:
  - `parse_oc_vars(raw_values: list[str]) -> dict[str, str]`
  - `make_oc_parser() -> argparse.ArgumentParser`
  - `main_oc(args: argparse.Namespace) -> int`
  - Top-level `parse_args(argv)` recognizes `oc` as a method/subcommand without breaking existing methods.

- [ ] **Step 1: Write the failing `tests/http-oc-test.sh` harness**

Create `tests/http-oc-test.sh` with this content:

```bash
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

echo "OK"
```

- [ ] **Step 2: Make the new test executable**

Run:

```bash
chmod +x tests/http-oc-test.sh
```

- [ ] **Step 3: Run the new test and verify it fails for missing `oc` support**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: fails with argparse invalid choice or missing OpenCollection behavior.

- [ ] **Step 4: Add parser support and a minimal `main_oc` stub**

Edit `general/bin/http`. Replace `parse_args` with a version that special-cases `oc` before the existing method parser:

```python
def make_oc_parser():
    p = argparse.ArgumentParser(prog="http oc", description="Run OpenCollection request")
    p.add_argument("request_name", nargs="?", default=None)
    p.add_argument("-c", "--collection", dest="collection", default=None)
    p.add_argument("-e", "--environment", dest="environment", default=None)
    p.add_argument("-v", "--var", dest="vars", action="append", default=[])
    p.add_argument("--no-interactive", dest="no_interactive", action="store_true")
    p.add_argument("-n", "--dry-run", dest="dry_run", action="store_true")
    p.add_argument("-i", "--include", dest="include", action="store_true")
    p.add_argument("-k", "--insecure", dest="insecure", action="store_true")
    p.add_argument("-L", "--follow", dest="follow", action="store_true")
    p.add_argument("-H", "--header", dest="headers", action="append", default=[])
    p.add_argument("-q", "--query", dest="queries", action="append", default=[])
    return p


def parse_oc_vars(raw_values):
    out = {}
    for raw in raw_values or []:
        for item in raw.split(","):
            if not item:
                continue
            if "=" not in item:
                print(f"error: --var expects KEY=VALUE, got: {item!r}", file=sys.stderr)
                sys.exit(2)
            key, value = item.split("=", 1)
            if not key:
                print("error: --var key cannot be empty", file=sys.stderr)
                sys.exit(2)
            out[key] = value
    return out


def parse_args(argv):
    if argv and argv[0] == "oc":
        args = make_oc_parser().parse_args(argv[1:])
        args.method = "oc"
        return args
    parser = argparse.ArgumentParser(prog="http", description=__doc__)
    sub = parser.add_subparsers(dest="method", required=True)
    for m in ("get", "post", "put", "patch", "delete"):
        sub.add_parser(m, parents=[SHARED_ARGS])
    return parser.parse_args(argv)
```

Then add this temporary `main_oc` near `main`:

```python
def main_oc(args):
    _ = parse_oc_vars(args.vars)
    print("error: http oc is not implemented yet", file=sys.stderr)
    return 2
```

And add this branch at the start of `main` after parsing:

```python
    if args.method == "oc":
        return main_oc(args)
```

- [ ] **Step 5: Run existing direct CLI tests**

Run:

```bash
bash tests/http-test.sh
```

Expected: `OK`.

- [ ] **Step 6: Commit parser skeleton and harness**

Run:

```bash
git add -f general/bin/http tests/http-oc-test.sh
git -c commit.gpgsign=false commit -m "feat(http): add oc parser skeleton and test harness"
```

---

### Task 2: Load `.httprc`, discover collections, and select by `-c`

**Files:**

- Modify: `general/bin/http`
- Modify: `tests/http-oc-test.sh`

**Interfaces:**

- Consumes: `main_oc(args) -> int`, `parse_oc_vars(raw_values) -> dict[str, str]`.
- Produces:
  - `OC_MANIFEST_NAMES = (...)`
  - `load_yaml_file(path: Path) -> dict`
  - `load_httprc(home: Path) -> dict`
  - `expand_config_path(value: str) -> Path`
  - `discover_collections(roots: list[Path]) -> list[dict]`
  - `select_collection(collections: list[dict], name: str | None, interactive: bool) -> dict`

- [ ] **Step 1: Extend tests for missing rc and collection fallback name**

Append before final `echo "OK"` in `tests/http-oc-test.sh`:

```bash
# ---------- Test 2: missing .httprc is a clear error ----------
echo "test 2: missing .httprc is a clear error"
setup_oc_tmp
rm -f "$OC_HOME/.config/.httprc"
run_http_oc_expect_fail --no-interactive -c collectionA -n get-smart-conditions
[ "$OC_EXIT" -eq 2 ] || { echo "FAIL: expected exit 2" >&2; exit 1; }
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
```

- [ ] **Step 2: Run new tests and verify they fail**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: still fails because `main_oc` is not implemented.

- [ ] **Step 3: Add YAML loading and collection discovery helpers**

Edit `general/bin/http` imports:

```python
import json
import shutil
import time
import hashlib
```

Add PyYAML import after stdlib imports:

```python
try:
    import yaml
except ImportError:  # pragma: no cover - exercised manually in environments without PyYAML
    yaml = None
```

Add helpers before `main_oc`:

```python
OC_MANIFEST_NAMES = (
    "opencollection.yaml",
    "opencollection.yml",
    "collection.yaml",
    "collection.yml",
)


def die(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(2)


def load_yaml_file(path):
    if yaml is None:
        die("PyYAML is required for http oc")
    try:
        with path.open(encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except FileNotFoundError:
        die(f"YAML file not found: {path}")
    except Exception as e:
        die(f"invalid YAML in {path}: {e}")
    return data or {}


def expand_config_path(value):
    return Path(os.path.expandvars(os.path.expanduser(str(value))))


def load_httprc(home):
    path = home / ".config" / ".httprc"
    if not path.is_file():
        die("~/.config/.httprc not found; expected YAML with a collections: list")
    data = load_yaml_file(path)
    roots = data.get("collections")
    if not isinstance(roots, list):
        die("~/.config/.httprc must contain collections: as a list")
    return {"path": path, "roots": [expand_config_path(p) for p in roots]}


def find_collection_manifest(directory):
    for name in OC_MANIFEST_NAMES:
        candidate = directory / name
        if candidate.is_file():
            return candidate
    return None


def discover_collections(roots):
    found = []
    for root in roots:
        if not root.is_dir():
            continue
        for current, dirs, _files in os.walk(root):
            current_path = Path(current)
            manifest = find_collection_manifest(current_path)
            if not manifest:
                continue
            data = load_yaml_file(manifest)
            info = data.get("info") if isinstance(data.get("info"), dict) else {}
            name = info.get("name") or current_path.name
            found.append({
                "name": str(name),
                "path": current_path,
                "manifest_path": manifest,
                "manifest": data,
            })
            dirs[:] = []
    return found


def select_collection(collections, name, interactive):
    if not collections:
        die("no collections discovered from ~/.config/.httprc roots")
    if name:
        matches = [c for c in collections if c["name"] == name or c["path"].name == name]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            if interactive:
                return choose_with_fzf_or_prompt(matches, "collection", lambda c: f"{c['name']}\t{c['path']}")
            die("collection name is ambiguous: " + ", ".join(str(c["path"]) for c in matches))
        die("collection not found: " + name + "; available: " + ", ".join(c["name"] for c in collections))
    if interactive:
        return choose_with_fzf_or_prompt(collections, "collection", lambda c: f"{c['name']}\t{c['path']}")
    die("collection is required; pass -c/--collection")
```

- [ ] **Step 4: Add non-interactive chooser placeholder used by collection selection**

Add this helper before `select_collection`:

```python
def choose_with_fzf_or_prompt(items, label, format_item):
    if not items:
        die(f"no {label} choices available")
    # Full fzf behavior is added in a later task. For now, a single item can be selected.
    if len(items) == 1:
        return items[0]
    die(f"interactive {label} selection is not implemented yet; pass an explicit value")
```

- [ ] **Step 5: Wire collection loading into `main_oc` while still failing at request phase**

Replace temporary `main_oc` with:

```python
def main_oc(args):
    parse_oc_vars(args.vars)
    interactive = (not args.no_interactive) and sys.stdin.isatty() and sys.stdout.isatty()
    config = load_httprc(Path.home())
    collections = discover_collections(config["roots"])
    collection = select_collection(collections, args.collection, interactive)
    print(f"error: request discovery is not implemented for collection {collection['name']}", file=sys.stderr)
    return 2
```

- [ ] **Step 6: Run tests and observe first test still fails later in flow**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: Test 2 passes; Test 1 or 3 now fails with `request discovery is not implemented`.

- [ ] **Step 7: Run direct CLI regression tests**

Run:

```bash
bash tests/http-test.sh
```

Expected: `OK`.

- [ ] **Step 8: Commit collection discovery**

Run:

```bash
git add -f general/bin/http tests/http-oc-test.sh
git -c commit.gpgsign=false commit -m "feat(http): discover OpenCollection roots from httprc"
```

---

### Task 3: Discover request YAML files and select request by basename

**Files:**

- Modify: `general/bin/http`
- Modify: `tests/http-oc-test.sh`

**Interfaces:**

- Consumes: `load_yaml_file(path)`, `choose_with_fzf_or_prompt(...)`, selected collection dict.
- Produces:
  - `is_collection_manifest(path: Path) -> bool`
  - `is_http_request_doc(data: dict) -> bool`
  - `discover_requests(collection: dict) -> list[dict]`
  - `select_request(requests: list[dict], name: str | None, interactive: bool) -> dict`

- [ ] **Step 1: Add tests for missing request in non-interactive mode and unknown request**

Append before final `echo "OK"`:

```bash
# ---------- Test 4: request name is required in non-interactive mode ----------
echo "test 4: request name required non-interactive"
setup_oc_tmp
write_basic_collection
run_http_oc_expect_fail --no-interactive -c collectionA -e development -n
[ "$OC_EXIT" -eq 2 ] || { echo "FAIL: expected exit 2" >&2; exit 1; }
assert_contains "$OC_STDERR" "request name is required" "missing request should be clear"

# ---------- Test 5: unknown request lists available requests ----------
echo "test 5: unknown request lists available"
setup_oc_tmp
write_basic_collection
run_http_oc_expect_fail --no-interactive -c collectionA -e development -n nope
[ "$OC_EXIT" -eq 2 ] || { echo "FAIL: expected exit 2" >&2; exit 1; }
assert_contains "$OC_STDERR" "request not found: nope" "unknown request error"
assert_contains "$OC_STDERR" "get-smart-conditions" "available request listed"
```

- [ ] **Step 2: Add request discovery helpers**

Edit `general/bin/http` and add after `select_collection`:

```python
def is_collection_manifest(path):
    return path.name in OC_MANIFEST_NAMES


def is_http_request_doc(data):
    if not isinstance(data, dict):
        return False
    if data.get("type") == "http":
        return True
    request = data.get("request")
    return isinstance(request, dict) and ("method" in request or "url" in request)


def discover_requests(collection):
    found = []
    base = collection["path"]
    for current, _dirs, files in os.walk(base):
        for filename in files:
            path = Path(current) / filename
            if path.suffix.lower() not in (".yaml", ".yml"):
                continue
            if is_collection_manifest(path):
                continue
            data = load_yaml_file(path)
            if not is_http_request_doc(data):
                continue
            found.append({
                "name": path.stem,
                "path": path,
                "data": data,
                "display": data.get("name") or path.stem,
            })
    return sorted(found, key=lambda r: r["name"])


def select_request(requests, name, interactive):
    if not requests:
        die("no HTTP request YAML files discovered in collection")
    if name:
        matches = [r for r in requests if r["name"] == name or r["display"] == name]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            if interactive:
                return choose_with_fzf_or_prompt(matches, "request", lambda r: f"{r['name']}\t{r['path']}")
            die("request name is ambiguous: " + ", ".join(str(r["path"]) for r in matches))
        die("request not found: " + name + "; available: " + ", ".join(r["name"] for r in requests))
    if interactive:
        return choose_with_fzf_or_prompt(requests, "request", lambda r: f"{r['name']}\t{r['path']}")
    die("request name is required in --no-interactive mode")
```

- [ ] **Step 3: Wire request discovery into `main_oc`**

Replace the end of `main_oc` with:

```python
    requests = discover_requests(collection)
    request = select_request(requests, args.request_name, interactive)
    print(f"error: environment resolution is not implemented for request {request['name']}", file=sys.stderr)
    return 2
```

Keep the preceding config/collection lines intact.

- [ ] **Step 4: Run tests and observe failure moves to environment/request building**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: request selection tests pass; Test 1 fails with `environment resolution is not implemented`.

- [ ] **Step 5: Run direct CLI regression tests**

Run:

```bash
bash tests/http-test.sh
```

Expected: `OK`.

- [ ] **Step 6: Commit request discovery**

Run:

```bash
git add -f general/bin/http tests/http-oc-test.sh
git -c commit.gpgsign=false commit -m "feat(http): discover OpenCollection request YAML files"
```

---

### Task 4: Resolve environment and variables, then build basic GET curl command

**Files:**

- Modify: `general/bin/http`
- Modify: `tests/http-oc-test.sh`

**Interfaces:**

- Consumes: selected collection/request dicts, `apply_template(text, variables)`.
- Produces:
  - `variables_list_to_dict(values) -> dict[str, str]`
  - `get_collection_variables(collection_manifest: dict) -> dict[str, str]`
  - `get_request_variables(request_doc: dict) -> dict[str, str]`
  - `get_environments(collection_manifest: dict) -> list[dict]`
  - `select_environment(environments, name, interactive) -> dict | None`
  - `find_template_variables(value) -> set[str]`
  - `collect_missing_variables(values, variables) -> set[str]`
  - `resolve_oc_variables(collection, request, environment, cli_vars, interactive) -> dict[str, str]`
  - `build_basic_oc_args(args, request_doc, variables) -> argparse.Namespace`

- [ ] **Step 1: Add variable precedence and missing variable tests**

Append before final `echo "OK"`:

```bash
# ---------- Test 6: CLI vars override environment vars and comma-separated vars work ----------
echo "test 6: cli vars override environment"
setup_oc_tmp
write_basic_collection
run_http_oc --no-interactive -c collectionA -e development -v "customerId=cli-customer,defaultHeader=cli-header" -n get-smart-conditions
assert_contains "$OC_STDOUT" "https://dev.example.com/smart-conditions/cli-customer" "CLI customer should win"
assert_contains "$OC_STDOUT" "X-Default: cli-header" "CLI header var should win"

# ---------- Test 7: missing variable fails in non-interactive mode ----------
echo "test 7: missing variable non-interactive"
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
[ "$OC_EXIT" -eq 2 ] || { echo "FAIL: expected exit 2" >&2; exit 1; }
assert_contains "$OC_STDERR" "missing variables" "missing variable error"
assert_contains "$OC_STDERR" "missingValue" "missing variable name"
```

- [ ] **Step 2: Add variable/environment helpers**

Add after request selection helpers:

```python
def variables_list_to_dict(values):
    out = {}
    if not isinstance(values, list):
        return out
    for item in values:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        if name is None:
            continue
        out[str(name)] = str(item.get("value", ""))
    return out


def get_collection_variables(collection_manifest):
    return variables_list_to_dict(collection_manifest.get("variables"))


def get_request_variables(request_doc):
    out = variables_list_to_dict(request_doc.get("variables"))
    request = request_doc.get("request") if isinstance(request_doc.get("request"), dict) else {}
    out.update(variables_list_to_dict(request.get("variables")))
    return out


def get_environments(collection_manifest):
    config = collection_manifest.get("config") if isinstance(collection_manifest.get("config"), dict) else {}
    envs = config.get("environments") or []
    return [e for e in envs if isinstance(e, dict) and e.get("name")]


def select_environment(environments, name, interactive):
    if name:
        matches = [e for e in environments if e.get("name") == name]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            die("environment name is ambiguous: " + name)
        die("environment not found: " + name + "; available: " + ", ".join(str(e.get("name")) for e in environments))
    if not environments:
        return None
    if len(environments) == 1:
        return environments[0]
    if interactive:
        return choose_with_fzf_or_prompt(environments, "environment", lambda e: str(e.get("name")))
    die("environment is required when multiple environments exist; pass -e/--environment")


def find_template_variables(value):
    found = set()
    if isinstance(value, str):
        found.update(m.group(1) for m in _TEMPLATE_RE.finditer(value))
    elif isinstance(value, dict):
        for child in value.values():
            found.update(find_template_variables(child))
    elif isinstance(value, list):
        for child in value:
            found.update(find_template_variables(child))
    return found


def prompt_missing_variables(missing):
    values = {}
    for name in sorted(missing):
        values[name] = input(f"value for {name}: ")
    return values


def resolve_oc_variables(collection, request, environment, cli_vars, interactive):
    variables = {}
    variables.update(get_collection_variables(collection["manifest"]))
    variables.update(get_request_variables(request["data"]))
    if environment:
        variables.update(variables_list_to_dict(environment.get("variables")))
    variables.update(cli_vars)
    missing = find_template_variables(request["data"]) - set(variables)
    if missing:
        if interactive:
            variables.update(prompt_missing_variables(missing))
        else:
            die("missing variables: " + ", ".join(sorted(missing)))
    return variables
```

- [ ] **Step 3: Add basic OpenCollection-to-args builder**

Add after variable helpers:

```python
def make_direct_args_from_oc(method, url, headers, queries, body, passthrough_args):
    ns = argparse.Namespace()
    ns.method = method.lower()
    ns.base_url = url
    ns.path = ""
    ns.token = None
    ns.headers = headers + list(passthrough_args.headers or [])
    ns.queries = queries + list(passthrough_args.queries or [])
    ns.file = None
    ns.data = body
    ns.vars = []
    ns.include = passthrough_args.include
    ns.dry_run = passthrough_args.dry_run
    ns.insecure = passthrough_args.insecure
    ns.follow = passthrough_args.follow
    return ns


def build_basic_oc_args(args, request_doc, variables):
    request = request_doc.get("request") if isinstance(request_doc.get("request"), dict) else {}
    method = str(request.get("method") or "GET")
    url = apply_template(str(request.get("url") or ""), variables)
    if not url:
        die("request.url is required")
    headers = []
    for header in request.get("headers") or []:
        if not isinstance(header, dict) or header.get("disabled") is True:
            continue
        name = header.get("name")
        value = header.get("value")
        if name is None or value is None:
            continue
        headers.append(f"{apply_template(str(name), variables)}: {apply_template(str(value), variables)}")
    queries = []
    for param in request.get("params") or []:
        if not isinstance(param, dict) or param.get("disabled") is True:
            continue
        if param.get("type") == "path":
            continue
        if param.get("type", "query") != "query":
            continue
        name = param.get("name")
        value = param.get("value", "")
        if name is None:
            continue
        queries.append(f"{apply_template(str(name), variables)}={apply_template(str(value), variables)}")
    return make_direct_args_from_oc(method, url, headers, queries, None, args)
```

- [ ] **Step 4: Wire environment/variables/basic curl into `main_oc`**

Replace the end of `main_oc` after request selection with:

```python
    environments = get_environments(collection["manifest"])
    environment = select_environment(environments, args.environment, interactive)
    cli_vars = parse_oc_vars(args.vars)
    variables = resolve_oc_variables(collection, request, environment, cli_vars, interactive)
    direct_args = build_basic_oc_args(args, request["data"], variables)
    curl_args = build_curl_args(direct_args, direct_args.base_url)
    if args.dry_run:
        print(format_curl_command(curl_args))
        return 0
    result = subprocess.run(["curl", *curl_args])
    return result.returncode
```

- [ ] **Step 5: Run OpenCollection tests**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: Tests 1-7 pass and print `OK`.

- [ ] **Step 6: Run direct CLI regression tests**

Run:

```bash
bash tests/http-test.sh
```

Expected: `OK`.

- [ ] **Step 7: Commit variable/environment basics**

Run:

```bash
git add -f general/bin/http tests/http-oc-test.sh
git -c commit.gpgsign=false commit -m "feat(http): resolve OpenCollection environments and variables"
```

---

### Task 5: Support raw body, Content-Type defaults, disabled entries, and path params

**Files:**

- Modify: `general/bin/http`
- Modify: `tests/http-oc-test.sh`

**Interfaces:**

- Consumes: `build_basic_oc_args(args, request_doc, variables)`.
- Produces:
  - `has_header(headers: list[str], header_name: str) -> bool` reused existing helper.
  - `content_type_for_oc_body(body_type: str) -> str | None`
  - `add_path_params_to_variables(request_doc, variables) -> dict[str, str]`

- [ ] **Step 1: Add tests for body, Content-Type, disabled entries, path params, and CLI append order**

Append before final `echo "OK"`:

```bash
# ---------- Test 8: raw JSON body, disabled entries, CLI headers and query ----------
echo "test 8: body disabled entries and CLI append"
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
      value: yes
    - name: X-Disabled
      value: no
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
assert_contains "$OC_STDOUT" "X-CLI: yes" "CLI header appended"
assert_contains "$OC_STDOUT" "Content-Type: application/json" "json body content type"
assert_contains "$OC_STDOUT" "--data" "body data flag present"
assert_contains "$OC_STDOUT" '"name":"book"' "body variable resolved"
assert_not_contains "$OC_STDOUT" "X-Disabled" "disabled header ignored"
assert_not_contains "$OC_STDOUT" "disabled=1" "disabled query ignored"

# ---------- Test 9: explicit Content-Type is not overridden ----------
echo "test 9: explicit content type wins"
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
```

- [ ] **Step 2: Add body/path helper functions**

Add after `make_direct_args_from_oc`:

```python
def content_type_for_oc_body(body_type):
    return {
        "json": "application/json",
        "xml": "application/xml",
        "text": "text/plain",
        "sparql": "application/sparql-query",
    }.get(body_type)


def add_path_params_to_variables(request_doc, variables):
    out = dict(variables)
    request = request_doc.get("request") if isinstance(request_doc.get("request"), dict) else {}
    for param in request.get("params") or []:
        if not isinstance(param, dict) or param.get("disabled") is True:
            continue
        if param.get("type") != "path":
            continue
        name = param.get("name")
        if name is None:
            continue
        out[str(name)] = apply_template(str(param.get("value", "")), out)
    return out
```

- [ ] **Step 3: Extend `build_basic_oc_args` for path params and raw body**

At the top of `build_basic_oc_args`, after `request = ...`, add:

```python
    variables = add_path_params_to_variables(request_doc, variables)
```

Before returning from `build_basic_oc_args`, replace `return make_direct_args_from_oc(..., None, args)` with body-aware code:

```python
    body_value = None
    body = request.get("body")
    if body is not None:
        if not isinstance(body, dict):
            die("unsupported request.body shape; expected object with type and data")
        body_type = str(body.get("type") or "")
        if body_type not in ("json", "xml", "text", "sparql"):
            die("unsupported request.body type for MVP: " + body_type)
        body_value = apply_template(str(body.get("data", "")), variables)
        default_ct = content_type_for_oc_body(body_type)
        combined_headers = headers + list(args.headers or [])
        if default_ct and not has_header(combined_headers, "Content-Type"):
            headers.append(f"Content-Type: {default_ct}")
    return make_direct_args_from_oc(method, url, headers, queries, body_value, args)
```

- [ ] **Step 4: Run OpenCollection tests**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: all tests pass.

- [ ] **Step 5: Run direct CLI regression tests**

Run:

```bash
bash tests/http-test.sh
```

Expected: `OK`.

- [ ] **Step 6: Commit body and params support**

Run:

```bash
git add -f general/bin/http tests/http-oc-test.sh
git -c commit.gpgsign=false commit -m "feat(http): build OpenCollection body headers and params"
```

---

### Task 6: Add non-interactive error coverage for unsupported auth/body and implement unsupported auth guard

**Files:**

- Modify: `general/bin/http`
- Modify: `tests/http-oc-test.sh`

**Interfaces:**

- Consumes request/collection manifest auth fields.
- Produces:
  - `get_oc_auth(collection_manifest: dict, request_doc: dict) -> dict | None`
  - `validate_supported_oc_auth(auth: dict | None) -> None`

- [ ] **Step 1: Add tests for unsupported body and auth types**

Append before final `echo "OK"`:

```bash
# ---------- Test 10: unsupported body type errors ----------
echo "test 10: unsupported body type"
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

# ---------- Test 11: unsupported auth type errors ----------
echo "test 11: unsupported auth type"
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
```

- [ ] **Step 2: Add auth helper functions**

Add after variable helpers:

```python
def get_oc_auth(collection_manifest, request_doc):
    if isinstance(request_doc.get("auth"), dict):
        return request_doc.get("auth")
    request = request_doc.get("request") if isinstance(request_doc.get("request"), dict) else {}
    if isinstance(request.get("auth"), dict):
        return request.get("auth")
    defaults = collection_manifest.get("request") if isinstance(collection_manifest.get("request"), dict) else {}
    if isinstance(defaults.get("auth"), dict):
        return defaults.get("auth")
    return None


def validate_supported_oc_auth(auth):
    if auth is None:
        return
    auth_type = auth.get("type")
    if auth_type != "oauth2":
        die("unsupported auth type for MVP: " + str(auth_type))
    grant_type = auth.get("grantType") or auth.get("grant_type")
    if grant_type not in ("client_credentials", "authorization_code"):
        die("unsupported oauth2 grant type for MVP: " + str(grant_type))
```

- [ ] **Step 3: Wire auth validation before building request**

In `main_oc`, after resolving variables and before `build_basic_oc_args`, add:

```python
    auth = get_oc_auth(collection["manifest"], request["data"])
    validate_supported_oc_auth(auth)
```

- [ ] **Step 4: Run OpenCollection tests**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: all tests pass.

- [ ] **Step 5: Run direct CLI regression tests**

Run:

```bash
bash tests/http-test.sh
```

Expected: `OK`.

- [ ] **Step 6: Commit unsupported guard behavior**

Run:

```bash
git add -f general/bin/http tests/http-oc-test.sh
git -c commit.gpgsign=false commit -m "feat(http): validate OpenCollection MVP auth and body scope"
```

---

### Task 7: Implement OAuth2 client credentials with cache

**Files:**

- Modify: `general/bin/http`
- Modify: `tests/http-oc-test.sh`

**Interfaces:**

- Consumes: `get_oc_auth`, `validate_supported_oc_auth`, `apply_template`, variable map.
- Produces:
  - `cache_key_for_auth(collection, environment, auth) -> str`
  - `load_cached_token(cache_dir: Path, key: str, now: float | None = None) -> str | None`
  - `save_cached_token(cache_dir: Path, key: str, token_response: dict, now: float | None = None) -> None`
  - `run_client_credentials(auth: dict) -> dict`
  - `resolve_oauth2_token(collection, environment, auth, variables) -> str | None`

- [ ] **Step 1: Add OAuth client credentials and cache tests**

Append before final `echo "OK"`:

```bash
# ---------- Test 12: oauth2 client credentials adds bearer token ----------
echo "test 12: oauth2 client credentials"
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
assert_contains "$OC_STDOUT" "Authorization: Bearer stub-token" "bearer token from oauth stub"

# ---------- Test 13: oauth2 token cache is reused ----------
echo "test 13: oauth2 cache reused"
run_http_oc --no-interactive -c collectionA -n secure
assert_contains "$OC_STDOUT" "Authorization: Bearer stub-token" "cached bearer token reused"
```

- [ ] **Step 2: Add cache and client credentials functions**

Add after auth validation helpers:

```python
def cache_key_for_auth(collection, environment, auth):
    env_name = environment.get("name") if environment else ""
    parts = [
        str(collection["path"]),
        str(env_name),
        str(auth.get("grantType") or auth.get("grant_type") or ""),
        str(auth.get("tokenUrl") or ""),
        str(auth.get("clientId") or ""),
        str(auth.get("scope") or ""),
    ]
    raw = "\0".join(parts).encode("utf-8")
    return hashlib.sha256(raw).hexdigest() + ".json"


def load_cached_token(cache_dir, key, now=None):
    now = time.time() if now is None else now
    path = cache_dir / key
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    expires_at = data.get("expires_at")
    token = data.get("access_token")
    if not token or not expires_at:
        return None
    if float(expires_at) <= now + 60:
        return None
    return str(token)


def save_cached_token(cache_dir, key, token_response, now=None):
    now = time.time() if now is None else now
    token = token_response.get("access_token")
    expires_in = token_response.get("expires_in")
    if not token or expires_in is None:
        return
    cache_dir.mkdir(parents=True, exist_ok=True)
    data = {
        "access_token": token,
        "token_type": token_response.get("token_type", "Bearer"),
        "expires_at": now + int(expires_in),
    }
    (cache_dir / key).write_text(json.dumps(data), encoding="utf-8")


def run_client_credentials(auth):
    cmd = [
        "curl",
        "--silent",
        "--show-error",
        "--fail",
        "-X",
        "POST",
        str(auth.get("tokenUrl")),
        "-H",
        "Content-Type: application/x-www-form-urlencoded",
        "-d",
        "grant_type=client_credentials",
        "-d",
        "client_id=" + str(auth.get("clientId")),
        "-d",
        "client_secret=" + str(auth.get("clientSecret")),
    ]
    if auth.get("scope"):
        cmd += ["-d", "scope=" + str(auth.get("scope"))]
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr, end="")
        die("oauth2 client_credentials token request failed")
    try:
        data = json.loads(result.stdout)
    except Exception as e:
        die(f"oauth2 token response was not JSON: {e}")
    if not data.get("access_token"):
        die("access_token not found in oauth2 token response")
    return data


def resolve_oauth2_token(collection, environment, auth, variables):
    if auth is None:
        return None
    resolved = {}
    for key, value in auth.items():
        resolved[key] = apply_template(str(value), variables) if isinstance(value, str) else value
    grant_type = resolved.get("grantType") or resolved.get("grant_type")
    cache_dir = Path.home() / ".cache" / "http-oc"
    key = cache_key_for_auth(collection, environment, resolved)
    cached = load_cached_token(cache_dir, key)
    if cached:
        return cached
    if grant_type == "client_credentials":
        token_response = run_client_credentials(resolved)
    elif grant_type == "authorization_code":
        token_response = run_authorization_code(resolved)
    else:
        die("unsupported oauth2 grant type for MVP: " + str(grant_type))
    save_cached_token(cache_dir, key, token_response)
    return str(token_response.get("access_token"))
```

- [ ] **Step 3: Add temporary authorization code placeholder**

Add after `run_client_credentials`:

```python
def run_authorization_code(auth):
    _ = auth
    die("authorization_code OAuth2 is not implemented yet")
```

- [ ] **Step 4: Wire token resolution into `main_oc`**

After `validate_supported_oc_auth(auth)`, add:

```python
    token = resolve_oauth2_token(collection, environment, auth, variables)
```

After `direct_args = build_basic_oc_args(...)`, add:

```python
    if token:
        direct_args.headers.append(f"Authorization: Bearer {token}")
```

- [ ] **Step 5: Run OpenCollection tests**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: all tests pass.

- [ ] **Step 6: Run direct CLI regression tests**

Run:

```bash
bash tests/http-test.sh
```

Expected: `OK`.

- [ ] **Step 7: Commit client credentials and cache**

Run:

```bash
git add -f general/bin/http tests/http-oc-test.sh
git -c commit.gpgsign=false commit -m "feat(http): add OpenCollection OAuth client credentials cache"
```

---

### Task 8: Implement authorization code OAuth by calling existing helper

**Files:**

- Modify: `general/bin/http`
- Modify: `tests/http-oc-test.sh`

**Interfaces:**

- Consumes: `resolve_oauth2_token(...)`, existing `general/bin/auth-code-token` script.
- Produces: `run_authorization_code(auth: dict) -> dict` returns token response dict with at least `access_token` and optional `expires_in`.

- [ ] **Step 1: Add authorization code test using stub helper**

Append before final `echo "OK"`:

```bash
# ---------- Test 14: oauth2 authorization code calls helper and adds bearer ----------
echo "test 14: oauth2 authorization code"
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
assert_contains "$OC_STDOUT" "Authorization: Bearer auth-code-token" "auth code bearer token"
assert_contains "$AUTH_CODE_ARGS_FILE" "browser-client" "helper gets client id"
assert_contains "$AUTH_CODE_ARGS_FILE" "https://auth.example.com/authorize" "helper gets auth url"
assert_contains "$AUTH_CODE_ARGS_FILE" "https://auth.example.com/token" "helper gets token url"
```

- [ ] **Step 2: Replace authorization code placeholder**

Replace `run_authorization_code` with:

```python
def run_authorization_code(auth):
    helper = shutil.which("auth-code-token")
    if helper is None:
        local = Path(__file__).resolve().parent / "auth-code-token"
        helper = str(local) if local.is_file() else None
    if helper is None:
        die("auth-code-token helper not found on PATH or next to http")
    cmd = [
        helper,
        str(auth.get("clientId")),
        str(auth.get("authorizationUrl")),
        str(auth.get("tokenUrl")),
        "--json",
    ]
    if auth.get("scope"):
        cmd += ["--scope", str(auth.get("scope"))]
    if auth.get("redirectUri"):
        cmd += ["--redirect-uri", str(auth.get("redirectUri"))]
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr, end="")
        die("oauth2 authorization_code token request failed")
    try:
        data = json.loads(result.stdout)
    except Exception as e:
        die(f"authorization_code token response was not JSON: {e}")
    if not data.get("access_token"):
        die("access_token not found in authorization_code token response")
    return data
```

- [ ] **Step 3: Run OpenCollection tests**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: all tests pass.

- [ ] **Step 4: Run direct CLI regression tests**

Run:

```bash
bash tests/http-test.sh
```

Expected: `OK`.

- [ ] **Step 5: Commit authorization code support**

Run:

```bash
git add -f general/bin/http tests/http-oc-test.sh
git -c commit.gpgsign=false commit -m "feat(http): add OpenCollection OAuth authorization code"
```

---

### Task 9: Implement interactive selection, fzf fallback, missing variable prompts, and summary

**Files:**

- Modify: `general/bin/http`
- Modify: `tests/http-oc-test.sh`

**Interfaces:**

- Consumes: `choose_with_fzf_or_prompt(items, label, format_item)` placeholder.
- Produces:
  - `INTERACTIVE_USED` module-level flag or return metadata.
  - `run_fzf(lines: list[str]) -> int | None`
  - `choose_with_fzf_or_prompt(...)` supports fzf or numbered prompt.
  - `print_oc_summary(collection, environment, request, direct_args) -> None`.

- [ ] **Step 1: Add fzf selection test with stubbed fzf**

Append before final `echo "OK"`:

```bash
# ---------- Test 15: interactive fzf can choose collection and request ----------
echo "test 15: fzf selection"
setup_oc_tmp
write_basic_collection
cat >"$OC_BIN/fzf" <<'STUB'
#!/usr/bin/env bash
# Pick the first option from stdin.
IFS= read -r first
printf '%s\n' "$first"
STUB
chmod +x "$OC_BIN/fzf"
# Use script command if available to allocate a tty; otherwise skip this TTY-specific test.
if command -v script >/dev/null 2>&1; then
 set +e
 HOME="$OC_HOME" PATH="$OC_BIN:$PATH" CURL_ARGS_FILE="$OC_TMPDIR/curl.args" script -q /dev/null "$SCRIPT" oc -e development -n >"$OC_TMPDIR/script.out" 2>"$OC_TMPDIR/script.err"
 status=$?
 set -e
 [ "$status" -eq 0 ] || { echo "FAIL: interactive fzf command failed" >&2; cat "$OC_TMPDIR/script.err" >&2; exit 1; }
 assert_contains "$OC_TMPDIR/script.out" "Collection: collectionA" "summary should show collection"
 assert_contains "$OC_TMPDIR/script.out" "Request: get-smart-conditions" "summary should show request"
 assert_contains "$OC_TMPDIR/script.out" "https://dev.example.com/smart-conditions/env-customer" "dry run URL"
else
 echo "skip: script command not available"
fi
```

- [ ] **Step 2: Add interactive helpers and summary support**

Add module flag near constants:

```python
OC_INTERACTIVE_USED = False
```

Replace `choose_with_fzf_or_prompt` with:

```python
def run_fzf(lines):
    if shutil.which("fzf") is None:
        return None
    proc = subprocess.run(["fzf"], input="\n".join(lines) + "\n", text=True, capture_output=True)
    if proc.returncode != 0:
        return None
    selected = proc.stdout.rstrip("\n")
    if selected in lines:
        return lines.index(selected)
    return None


def choose_with_fzf_or_prompt(items, label, format_item):
    global OC_INTERACTIVE_USED
    if not items:
        die(f"no {label} choices available")
    if len(items) == 1:
        return items[0]
    lines = [format_item(item) for item in items]
    idx = run_fzf(lines)
    if idx is not None:
        OC_INTERACTIVE_USED = True
        return items[idx]
    print(f"Choose {label}:", file=sys.stderr)
    for i, line in enumerate(lines, start=1):
        print(f"  {i}) {line}", file=sys.stderr)
    raw = input(f"{label} number: ").strip()
    try:
        chosen = int(raw)
    except ValueError:
        die(f"invalid {label} selection: {raw}")
    if chosen < 1 or chosen > len(items):
        die(f"invalid {label} selection: {raw}")
    OC_INTERACTIVE_USED = True
    return items[chosen - 1]
```

Update `prompt_missing_variables`:

```python
def prompt_missing_variables(missing):
    global OC_INTERACTIVE_USED
    values = {}
    for name in sorted(missing):
        OC_INTERACTIVE_USED = True
        values[name] = input(f"value for {name}: ")
    return values
```

Add summary helper:

```python
def print_oc_summary(collection, environment, request, direct_args):
    env_name = environment.get("name") if environment else ""
    print(f"Collection: {collection['name']}")
    if env_name:
        print(f"Environment: {env_name}")
    print(f"Request: {request['name']}")
    print(f"{direct_args.method.upper()} {direct_args.base_url}")
```

- [ ] **Step 3: Print summary when interaction was used**

In `main_oc`, set the global flag at the start:

```python
    global OC_INTERACTIVE_USED
    OC_INTERACTIVE_USED = False
```

After `direct_args` and token header are prepared, before dry-run/live execution, add:

```python
    if OC_INTERACTIVE_USED:
        print_oc_summary(collection, environment, request, direct_args)
```

- [ ] **Step 4: Run OpenCollection tests**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: all non-skipped tests pass.

- [ ] **Step 5: Run direct CLI regression tests**

Run:

```bash
bash tests/http-test.sh
```

Expected: `OK`.

- [ ] **Step 6: Commit interactive UX**

Run:

```bash
git add -f general/bin/http tests/http-oc-test.sh
git -c commit.gpgsign=false commit -m "feat(http): add interactive OpenCollection selection UX"
```

---

### Task 10: Final verification, diagnostics, and cleanup

**Files:**

- Modify only if verification reveals small issues: `general/bin/http`, `tests/http-oc-test.sh`

**Interfaces:**

- Consumes all previous tasks.
- Produces a verified branch ready for review.

- [ ] **Step 1: Run Python compile check**

Run:

```bash
python3 -m py_compile general/bin/http
```

Expected: no output, exit 0.

- [ ] **Step 2: Run direct CLI tests**

Run:

```bash
bash tests/http-test.sh
```

Expected: prints test names and `OK`, exit 0.

- [ ] **Step 3: Run OpenCollection tests**

Run:

```bash
bash tests/http-oc-test.sh
```

Expected: prints test names and `OK`, exit 0. TTY-specific test may print a skip only if `script` is unavailable.

- [ ] **Step 4: Run LSP diagnostics on changed Python file**

Run tool-equivalent command if available in this session:

```bash
python3 -m py_compile general/bin/http
```

Expected: no output. If using pi-lens, also run `lens_diagnostics mode=all` before claiming completion.

- [ ] **Step 5: Inspect git diff for accidental unrelated changes**

Run:

```bash
git diff -- general/bin/http tests/http-oc-test.sh
```

Expected: diff contains only OpenCollection implementation/test changes.

- [ ] **Step 6: Commit final cleanup only if files changed in this task**

If Step 1-5 required edits, run:

```bash
git add -f general/bin/http tests/http-oc-test.sh
git -c commit.gpgsign=false commit -m "chore(http): verify OpenCollection MVP"
```

If no edits were required, do not create an empty commit.

---

## Self-Review

**1. Spec coverage:**

| Spec requirement | Covered by |
| --- | --- |
| Add `http oc` without regressing direct commands | Tasks 1-10, repeated `tests/http-test.sh` runs |
| Read `~/.config/.httprc` YAML | Task 2 |
| Discover collections by manifest names | Task 2 |
| Select collection by `info.name` or directory basename | Task 2 |
| Discover requests by YAML basename | Task 3 |
| Environment selection rules | Task 4 |
| Variable precedence and missing variable errors | Task 4 |
| CLI `-v` repeat/comma format | Tasks 1 and 4 |
| Build method URL headers query raw body | Tasks 4 and 5 |
| Disabled headers/params ignored | Task 5 |
| Path params become variables with `{{name}}` support | Task 5 |
| Content-Type defaults and explicit override | Task 5 |
| Unsupported body/auth errors | Task 6 |
| OAuth client credentials | Task 7 |
| OAuth token cache | Task 7 |
| OAuth authorization code via helper | Task 8 |
| Interactive fzf/prompt selection | Task 9 |
| Summary after interactive choices | Task 9 |
| `--no-interactive` deterministic errors | Tasks 2-4 and 6 |
| Dedicated `tests/http-oc-test.sh` | Task 1 onward |
| Final validation commands | Task 10 |

**2. Placeholder scan:** This plan contains no unresolved placeholder instructions. Code snippets define concrete functions and exact commands.

**3. Type consistency:** Helper signatures are introduced before use. Collection dicts consistently use `name`, `path`, `manifest_path`, `manifest`. Request dicts consistently use `name`, `path`, `data`, `display`. `main_oc(args)` remains the single entrypoint for `oc` mode. OAuth token functions return JSON dicts until `resolve_oauth2_token`, which returns `str | None`.
