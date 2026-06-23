# `jwt-decode` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small helper in `general/bin/jwt-decode` that accepts a JWT as a positional argument, decodes the payload segment, and prints formatted JSON with `jq`.

**Architecture:** Implement a single bash script that validates dependencies and input, extracts the second JWT segment, normalizes base64url to standard base64, decodes it, and pipes the result to `jq`. Cover the behavior with one shell test file that exercises success and the expected failure modes.

**Tech Stack:** Bash, `jq`, `base64`, shell tests in `tests/`.

## Global Constraints

- Production file must be `general/bin/jwt-decode`.
- Input is a single positional token: `jwt-decode <token>`.
- v1 decodes only the JWT payload segment (second part).
- Support JWT base64url encoding: `-` → `+`, `_` → `/`, and add `=` padding until the payload length is a multiple of 4.
- Pretty-print output with `jq`.
- Fail clearly for wrong arg count, missing `jq`/`base64`, malformed JWTs, decode failures, and invalid JSON payloads.
- Do not add stdin support, signature verification, header decoding, or claim validation.
- Follow TDD: write the failing test first, run it, then implement the minimum code to pass.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `general/bin/jwt-decode` | Shell CLI that decodes the JWT payload and formats it with `jq`. |
| `tests/jwt-decode-test.sh` | Shell test covering success, usage errors, malformed token handling, and invalid payload handling. |

---

### Task 1: Add the failing test for the new CLI

**Files:**

- Create: `tests/jwt-decode-test.sh`
- Test: `tests/jwt-decode-test.sh`

**Interfaces:**

- Consumes: executable `general/bin/jwt-decode`
- Produces: a repeatable shell test that calls the script with sample JWTs and validates stdout/stderr/exit codes

- [ ] **Step 1: Create `tests/jwt-decode-test.sh` with the test harness and expected behaviors**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/jwt-decode"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

run_ok() {
  local name="$1"
  shift
  "$SCRIPT" "$@" >"$TMPDIR/${name}.out" 2>"$TMPDIR/${name}.err"
}

run_fail() {
  local name="$1"
  shift
  set +e
  "$SCRIPT" "$@" >"$TMPDIR/${name}.out" 2>"$TMPDIR/${name}.err"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "Expected failure for $name" >&2
    exit 1
  fi
}

TOKEN_OK='eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjMiLCJuYW1lIjoiSm9obiBEb2UifQ.'
TOKEN_BAD_JSON='eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.bm90LWpzb24.'
TOKEN_BAD_SHAPE='not-a-jwt'

run_ok success "$TOKEN_OK"
python3 - "$TMPDIR/success.out" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

expected = {
    'sub': '123',
    'name': 'John Doe',
}
if data != expected:
    print('Decoded payload mismatch', file=sys.stderr)
    print(data, file=sys.stderr)
    sys.exit(1)
PY

run_fail usage
if ! grep -Fq 'Usage: jwt-decode <token>' "$TMPDIR/usage.err"; then
  echo 'Expected usage message on missing arg' >&2
  exit 1
fi

run_fail malformed "$TOKEN_BAD_SHAPE"
if ! grep -Fq 'Error: invalid JWT' "$TMPDIR/malformed.err"; then
  echo 'Expected invalid JWT error' >&2
  exit 1
fi

run_fail bad-json "$TOKEN_BAD_JSON"
if ! grep -Fq 'Error: invalid JWT payload JSON' "$TMPDIR/bad-json.err"; then
  echo 'Expected invalid JSON payload error' >&2
  exit 1
fi
```

- [ ] **Step 2: Make the test executable**

Run: `chmod +x tests/jwt-decode-test.sh`

- [ ] **Step 3: Run the test to verify RED**

Run: `bash tests/jwt-decode-test.sh`

Expected: FAIL because `general/bin/jwt-decode` does not exist yet.

- [ ] **Step 4: Commit the failing test scaffold**

```bash
git add -f tests/jwt-decode-test.sh
git -c commit.gpgsign=false commit -m "test(jwt-decode): add failing CLI coverage"
```

---

### Task 2: Implement the minimal `jwt-decode` script

**Files:**

- Create: `general/bin/jwt-decode`
- Modify: `tests/jwt-decode-test.sh` (only if the RED step exposed a test bug)
- Test: `tests/jwt-decode-test.sh`

**Interfaces:**

- Consumes: one positional JWT string
- Produces: formatted JSON on stdout; non-zero exit plus clear stderr message on failure

- [ ] **Step 1: Create `general/bin/jwt-decode` with the minimal implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo 'Usage: jwt-decode <token>' >&2
  exit 1
fi

for command in jq base64; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Error: required command '$command' not found" >&2
    exit 1
  fi
done

token="$1"
payload="$(printf '%s' "$token" | cut -d '.' -f 2)"

if [ -z "$payload" ] || [ "$payload" = "$token" ]; then
  echo 'Error: invalid JWT' >&2
  exit 1
fi

payload="$(printf '%s' "$payload" | tr '_-' '/+')"

case $((${#payload} % 4)) in
  0) ;;
  2) payload="${payload}==" ;;
  3) payload="${payload}=" ;;
  *)
    echo 'Error: failed to decode JWT payload' >&2
    exit 1
    ;;
esac

decoded="$({ printf '%s' "$payload" | base64 -d; } 2>/dev/null)" || {
  echo 'Error: failed to decode JWT payload' >&2
  exit 1
}

printf '%s' "$decoded" | jq . >/dev/null 2>&1 || {
  echo 'Error: invalid JWT payload JSON' >&2
  exit 1
}

printf '%s' "$decoded" | jq .
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x general/bin/jwt-decode`

- [ ] **Step 3: Run the test to verify GREEN**

Run: `bash tests/jwt-decode-test.sh`

Expected: PASS with no output other than any optional success echo you add to the test script.

- [ ] **Step 4: Do one manual smoke check with the happy-path token**

Run:

```bash
general/bin/jwt-decode 'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjMiLCJuYW1lIjoiSm9obiBEb2UifQ.'
```

Expected:

```json
{
  "sub": "123",
  "name": "John Doe"
}
```

- [ ] **Step 5: Commit the implementation**

```bash
git add -f general/bin/jwt-decode tests/jwt-decode-test.sh
git -c commit.gpgsign=false commit -m "feat(general): add jwt-decode helper"
```

---

### Task 3: Final verification and cleanup

**Files:**

- Verify: `general/bin/jwt-decode`
- Verify: `tests/jwt-decode-test.sh`

**Interfaces:**

- Consumes: completed script and test
- Produces: verified evidence that the helper works and is ready to keep

- [ ] **Step 1: Run the focused automated test again**

Run: `bash tests/jwt-decode-test.sh`

Expected: PASS.

- [ ] **Step 2: Run syntax/shell validation**

Run:

```bash
bash -n general/bin/jwt-decode
bash -n tests/jwt-decode-test.sh
```

Expected: both commands exit 0 with no output.

- [ ] **Step 3: Check the git diff before stopping**

Run:

```bash
git diff -- general/bin/jwt-decode tests/jwt-decode-test.sh
```

Expected: empty output if everything is already committed.

- [ ] **Step 4: If verification required any last fix, commit it**

```bash
git add -f general/bin/jwt-decode tests/jwt-decode-test.sh
git -c commit.gpgsign=false commit -m "chore(general): finalize jwt-decode verification"
```

Skip this step if there were no post-verification changes.

---

## Self-Review

- **Spec coverage:**
  - New CLI path in `general/bin/` → Task 2
  - Positional token input only → Task 1 + Task 2
  - Payload-only decoding with base64url normalization → Task 2
  - Pretty JSON via `jq` → Task 2 + Task 3 smoke check
  - Clear failures for usage, malformed JWT, invalid payload JSON → Task 1 tests + Task 2 implementation
- **Placeholder scan:** No `TODO`, `TBD`, or vague “handle errors” steps remain.
- **Interface consistency:** All tasks consistently reference `general/bin/jwt-decode` and `tests/jwt-decode-test.sh`.
