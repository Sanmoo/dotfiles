# `auth-code-token` Forced Reauthentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `general/bin/auth-code-token` with `--force-login` and repeatable `--auth-param key=value` so callers can request reauthentication and customize authorization request parameters without changing the default OAuth PKCE flow.

**Architecture:** Keep the change inside the existing Python CLI by adding a small parser for custom authorization parameters and merging them into the authorization request with explicit precedence. Cover the behavior by expanding the existing shell test to capture the generated authorization URL and assert the new query parameter semantics and error handling.

**Tech Stack:** Python standard library (`argparse`, `urllib.parse`), shell tests in `tests/`.

## Global Constraints

- Production file remains `general/bin/auth-code-token`.
- Add `--force-login` and repeatable `--auth-param key=value`.
- `--force-login` must add `prompt=login` and `max_age=0` to the authorization request.
- `--auth-param` must be able to override those defaults and add arbitrary provider-specific parameters.
- Do not allow user overrides of `response_type`, `client_id`, `redirect_uri`, `code_challenge`, `code_challenge_method`, or `state`.
- Preserve the current default flow when neither new option is used.
- Keep the change local to authorization request construction; do not add logout behavior or token exchange changes.
- Fail clearly for malformed `--auth-param` values and forbidden overrides.
- Follow TDD: write the failing test first, run it, then implement the minimum code to pass.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `general/bin/auth-code-token` | Python CLI that builds the authorization URL, launches the browser, receives the callback, and exchanges the code for tokens. This change adds CLI parsing and authorization parameter merge logic. |
| `tests/auth-code-token-test.sh` | Shell regression test that stubs browser/callback/token exchange behavior and verifies stdout plus generated authorization URL query parameters and new error cases. |

---

### Task 1: Add failing coverage for forced-login and custom auth parameters

**Files:**

- Modify: `tests/auth-code-token-test.sh:1-69`
- Test: `tests/auth-code-token-test.sh`

**Interfaces:**

- Consumes: executable `general/bin/auth-code-token`
- Produces: a shell regression test that captures the generated authorization URL and validates `--force-login`, `--auth-param`, malformed input, and protected parameter rejection

- [ ] **Step 1: Replace `tests/auth-code-token-test.sh` with a harness that records the opened authorization URL and exercises the new CLI surface**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/auth-code-token"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

run_auth_code_token() {
  local name="$1"
  shift
  AUTH_URL_CAPTURE="$TMPDIR/${name}.auth-url" \
    python - "$SCRIPT" "$@" >"$TMPDIR/${name}.out" 2>"$TMPDIR/${name}.err" <<'PY'
import importlib.machinery
import importlib.util
import os
import sys

script = sys.argv[1]
args = sys.argv[2:]
loader = importlib.machinery.SourceFileLoader('auth_code_token', script)
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

module.serve_callback = lambda port, path, state, timeout: 'auth-code'
module.post_form = lambda url, data: {
    'access_token': 'abc123',
    'refresh_token': 'refresh456',
    'token_type': 'Bearer',
    'expires_in': 3600,
}

def capture_open(url):
    with open(os.environ['AUTH_URL_CAPTURE'], 'w', encoding='utf-8') as f:
        f.write(url)
    return True

module.webbrowser.open = capture_open
module.main(args)
PY
}

run_fail() {
  local name="$1"
  shift
  set +e
  run_auth_code_token "$name" "$@"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "Expected failure for $name" >&2
    exit 1
  fi
}

assert_query_value() {
  local url_file="$1"
  local key="$2"
  local expected="$3"
  python3 - "$url_file" "$key" "$expected" <<'PY'
import sys
from urllib.parse import parse_qs, urlparse

with open(sys.argv[1], encoding='utf-8') as f:
    url = f.read().strip()
key = sys.argv[2]
expected = sys.argv[3]
values = parse_qs(urlparse(url).query, keep_blank_values=True).get(key)
if values != [expected]:
    print(f'Expected {key}={expected!r}, got {values!r}', file=sys.stderr)
    sys.exit(1)
PY
}

BASE_ARGS=(
  my-client
  https://auth.example/authorize
  https://auth.example/token
  --redirect-uri
  http://127.0.0.1:8765/callback
)

run_auth_code_token default "${BASE_ARGS[@]}"
if [ "$(cat "$TMPDIR/default.out")" != "abc123" ]; then
  echo "Expected default stdout to contain only access_token" >&2
  cat "$TMPDIR/default.out" >&2
  exit 1
fi
assert_query_value "$TMPDIR/default.auth-url" response_type code
assert_query_value "$TMPDIR/default.auth-url" client_id my-client

run_auth_code_token json "${BASE_ARGS[@]}" --json
python3 - "$TMPDIR/json.out" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)

expected = {
    'access_token': 'abc123',
    'refresh_token': 'refresh456',
    'token_type': 'Bearer',
    'expires_in': 3600,
}
if data != expected:
    print('Expected stdout to contain full token response JSON', file=sys.stderr)
    print(data, file=sys.stderr)
    sys.exit(1)
PY

run_auth_code_token force-login "${BASE_ARGS[@]}" --force-login
assert_query_value "$TMPDIR/force-login.auth-url" prompt login
assert_query_value "$TMPDIR/force-login.auth-url" max_age 0

run_auth_code_token override "${BASE_ARGS[@]}" \
  --force-login \
  --auth-param prompt=select_account \
  --auth-param max_age=3600 \
  --auth-param audience=https://api.example
assert_query_value "$TMPDIR/override.auth-url" prompt select_account
assert_query_value "$TMPDIR/override.auth-url" max_age 3600
assert_query_value "$TMPDIR/override.auth-url" audience https://api.example

run_fail malformed-auth-param "${BASE_ARGS[@]}" --auth-param prompt
if ! grep -Fq 'Error: --auth-param must use key=value format' "$TMPDIR/malformed-auth-param.err"; then
  echo 'Expected malformed --auth-param error' >&2
  cat "$TMPDIR/malformed-auth-param.err" >&2
  exit 1
fi

run_fail protected-param "${BASE_ARGS[@]}" --auth-param state=override
if ! grep -Fq "Error: --auth-param cannot override reserved parameter 'state'" "$TMPDIR/protected-param.err"; then
  echo 'Expected protected parameter rejection' >&2
  cat "$TMPDIR/protected-param.err" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the test to verify RED**

Run: `bash tests/auth-code-token-test.sh`

Expected: FAIL because `general/bin/auth-code-token` does not yet recognize `--force-login` or `--auth-param`, and the new assertions cannot pass.

- [ ] **Step 3: Commit the failing regression test**

```bash
git add tests/auth-code-token-test.sh
git -c commit.gpgsign=false commit -m "test(auth-code-token): cover force-login auth params"
```

---

### Task 2: Implement CLI parsing and authorization parameter merging

**Files:**

- Modify: `general/bin/auth-code-token:1-264`
- Test: `tests/auth-code-token-test.sh`

**Interfaces:**

- Consumes: `args.force_login: bool`, `args.auth_param: list[str] | None`, existing OAuth base arguments
- Produces:
  - `parse_auth_params(raw_values: list[str] | None) -> dict[str, str]`
  - `build_authorization_params(args, redirect_uri: str, challenge: str, state: str) -> dict[str, str]`
  - unchanged `main(argv=None)` output contract: access token on stdout by default, JSON with `--json`

- [ ] **Step 1: Add the new argparse options and helper functions inside `general/bin/auth-code-token`**

Insert these definitions near the constants and `parse_args()` section:

```python
FORCE_LOGIN_DEFAULTS = {
    'prompt': 'login',
    'max_age': '0',
}
PROTECTED_AUTH_PARAMS = {
    'response_type',
    'client_id',
    'redirect_uri',
    'code_challenge',
    'code_challenge_method',
    'state',
    'scope',
}


def parse_auth_params(raw_values):
    params = {}
    for raw in raw_values or []:
        if '=' not in raw:
            sys.exit('Error: --auth-param must use key=value format')
        key, value = raw.split('=', 1)
        if not key:
            sys.exit('Error: --auth-param key cannot be empty')
        if key in PROTECTED_AUTH_PARAMS:
            sys.exit(
                f"Error: --auth-param cannot override reserved parameter '{key}'"
            )
        params[key] = value
    return params


def build_authorization_params(args, redirect_uri, challenge, state):
    auth_params = {
        'response_type': 'code',
        'client_id': args.client_id,
        'redirect_uri': redirect_uri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
    }
    if args.scope:
        auth_params['scope'] = args.scope
    if args.force_login:
        auth_params.update(FORCE_LOGIN_DEFAULTS)
    auth_params.update(parse_auth_params(args.auth_param))
    return auth_params
```

Update `parse_args()` so it also includes:

```python
    parser.add_argument(
        '--force-login',
        action='store_true',
        help='Request reauthentication by adding prompt=login and max_age=0.',
    )
    parser.add_argument(
        '--auth-param',
        action='append',
        default=[],
        metavar='KEY=VALUE',
        help='Add or override a non-reserved authorization request parameter.',
    )
```

- [ ] **Step 2: Replace the inline `auth_params` construction in `main()` with the helper**

Change the current block:

```python
    auth_params = {
        'response_type': 'code',
        'client_id': args.client_id,
        'redirect_uri': redirect_uri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
    }
    if args.scope:
        auth_params['scope'] = args.scope
```

To this:

```python
    auth_params = build_authorization_params(args, redirect_uri, challenge, state)
```

Also update the module docstring usage block so the CLI synopsis includes the two new options:

```text
  authorization-code-token <client_id> <authorization_url> <token_url>
                         [--scope SCOPE] [--redirect-uri URI]
                         [--timeout SECONDS] [--no-browser] [--json]
                         [--force-login] [--auth-param KEY=VALUE]
```

- [ ] **Step 3: Run the focused test to verify GREEN**

Run: `bash tests/auth-code-token-test.sh`

Expected: PASS. The test should confirm:

- default stdout still prints `abc123`
- `--json` still prints the full token response
- `--force-login` adds `prompt=login` and `max_age=0`
- `--auth-param` overrides those defaults and appends `audience`
- malformed and protected custom parameters fail with the expected error messages

- [ ] **Step 4: Do one help-text smoke check**

Run:

```bash
python general/bin/auth-code-token --help > /tmp/auth-code-token-help.txt
rg -n -- '--force-login|--auth-param' /tmp/auth-code-token-help.txt
```

Expected:

- the Python command exits 0
- `rg` finds both new flags in the help output

- [ ] **Step 5: Commit the implementation**

```bash
git add general/bin/auth-code-token tests/auth-code-token-test.sh
git -c commit.gpgsign=false commit -m "feat(auth-code-token): support forced reauthentication"
```

---

### Task 3: Final verification and cleanup

**Files:**

- Verify: `general/bin/auth-code-token`
- Verify: `tests/auth-code-token-test.sh`

**Interfaces:**

- Consumes: completed CLI and updated regression test
- Produces: verification evidence that the new options work and the default flow remains intact

- [ ] **Step 1: Re-run the focused regression suite**

Run: `bash tests/auth-code-token-test.sh`

Expected: PASS.

- [ ] **Step 2: Run Python syntax validation**

Run:

```bash
python -m py_compile general/bin/auth-code-token
bash -n tests/auth-code-token-test.sh
```

Expected: both commands exit 0 with no output.

- [ ] **Step 3: Inspect the final diff**

Run:

```bash
git diff -- general/bin/auth-code-token tests/auth-code-token-test.sh
```

Expected: empty output if everything is committed.

- [ ] **Step 4: If verification required any follow-up fix, commit it**

```bash
git add general/bin/auth-code-token tests/auth-code-token-test.sh
git -c commit.gpgsign=false commit -m "chore(auth-code-token): finalize verification"
```

Skip this step if no post-verification changes were needed.

---

## Self-Review

- **Spec coverage:**
  - `--force-login` flag and portable defaults → Task 1 assertions + Task 2 implementation
  - repeatable `--auth-param key=value` → Task 1 assertions + Task 2 implementation
  - override precedence (`force-login` defaults overridden by custom params) → Task 1 `override` case + Task 2 merge order
  - protected OAuth/PKCE parameters rejected → Task 1 `protected-param` case + Task 2 `PROTECTED_AUTH_PARAMS`
  - malformed custom parameter input fails clearly → Task 1 `malformed-auth-param` case + Task 2 parser
  - unchanged default flow and JSON mode → Task 1 `default` and `json` cases + Task 3 regression rerun
- **Placeholder scan:** No `TODO`, `TBD`, or vague “handle errors” instructions remain.
- **Interface consistency:** All tasks consistently reference `parse_auth_params`, `build_authorization_params`, `general/bin/auth-code-token`, and `tests/auth-code-token-test.sh`.
