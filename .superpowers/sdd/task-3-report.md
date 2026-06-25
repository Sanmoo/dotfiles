Status: DONE_WITH_CONCERNS

Summary of edits:
- Added OpenCollection request discovery helpers in `general/bin/http`:
  - `is_collection_manifest(path)`
  - `is_http_request_doc(data)`
  - `discover_requests(collection)`
  - `select_request(requests, name, interactive)`
- Wired `main_oc` to discover request YAML files, select by basename/display name, and advance the intentional failure point to environment resolution/request building.
- Appended the requested request-selection coverage to `tests/http-oc-test.sh` without changing the existing placeholder assertion.

Exact test commands run and their output:

1. `bash tests/http-oc-test.sh`

```text
test 1: oc parser is available
test 2: missing .httprc is a clear error
test 3: invalid .httprc top-level shape is a clear error
test 4: invalid collection manifest top-level shape is a clear error
test 5: collection fallback directory name
test 4: request name required non-interactive
FAIL: missing request should be clear
  expected to find: request name is required
  in:
    error: request discovery is not implemented for collection collectionA
```

2. `bash tests/http-oc-test.sh`

```text
test 1: oc parser is available
FAIL: oc should reach the intentional request-discovery placeholder
  expected to find: request discovery is not implemented for collection collectionA
  in:
    error: environment resolution is not implemented for request get-smart-conditions
```

3. `bash tests/http-test.sh`

```text
test 1: simplest post
test 2: get emits no -X
test 3: delete emits -X DELETE
test 4: dedup of leading slash in path
test 5: -i, -k, -L pass through
test 6: -B flag precedence
test 7: HTTP_BASE_URL wins over BASE_URL
test 8: BASE_URL fallback
test 9: no base URL is an error
test 10: -H stacks
test 11: -t bearer
test 12: empty -t is an error
test 13: -t and explicit Authorization
test 14: single -q
test 15: multiple -q
test 16: -q URL-encoding
test 17: -d inline body
test 18: -f with auto Content-Type
test 19: -f .jsonc auto Content-Type
test 20: -f .xml auto Content-Type
test 21: -f other extension -> octet-stream
test 22: explicit Content-Type wins
test 23: -f and -d together is an error
test 24: -f with missing file is an error
test 25: -v in -d
test 26: -v in file body
test 27: undefined variable is an error
test 28: -v with empty value
test 29: dry-run output
test 30: dry-run shlex roundtrip
test 31: live execution hits the stub
test 32: .jsonc comments stripped
test 33: .jsonc preserves // in strings
test 34: GET defaults Content-Type to application/json
test 35: explicit Content-Type wins on GET
test 36: GET with -f keeps file-derived Content-Type
OK
```

4. `python3 -m py_compile general/bin/http`

```text
(no output)
```

5. Manual validation for the newly added request-selection paths:

```text
missing-request exit=2
error: request name is required in --no-interactive mode
unknown-request exit=2
error: request not found: nope; available: get-smart-conditions
```

Commits created:
- `e0ed66452a7eba4d338166c3d5d5a6ca51314a44` — `feat(http): discover OpenCollection request YAML files`

Concerns:
- `tests/http-oc-test.sh` is intentionally left failing at the older placeholder assertion in Test 1, matching the approved plan's expectation that the failure point moves to environment resolution/request building.
- The newly appended request-selection assertions are present and the underlying behavior was manually validated, but the script stops at Test 1 until the placeholder assertion is updated in a later task.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Implemented request YAML discovery and basename/display-name selection only in general/bin/http, kept direct CLI behavior intact, and moved the intentional http oc failure from collection-level request discovery to environment resolution for the selected request."
    }
  ],
  "changedFiles": [
    "general/bin/http",
    "tests/http-oc-test.sh"
  ],
  "testsAddedOrUpdated": [
    "tests/http-oc-test.sh"
  ],
  "commandsRun": [
    {
      "command": "bash tests/http-oc-test.sh",
      "result": "failed_as_expected",
      "summary": "Initial red test failed on missing request-name assertion before implementation."
    },
    {
      "command": "bash tests/http-oc-test.sh",
      "result": "failed_as_expected",
      "summary": "After implementation, Test 1 now fails at the moved placeholder: environment resolution is not implemented for request get-smart-conditions."
    },
    {
      "command": "bash tests/http-test.sh",
      "result": "passed",
      "summary": "Direct CLI regression suite passed with OK."
    },
    {
      "command": "python3 -m py_compile general/bin/http",
      "result": "passed",
      "summary": "Python syntax validation passed with no output."
    },
    {
      "command": "manual request-selection validation snippet",
      "result": "passed",
      "summary": "Verified missing request name and unknown request both exit 2 with the expected stderr messages."
    }
  ],
  "validationOutput": [
    "http oc now reports: error: environment resolution is not implemented for request get-smart-conditions",
    "Manual validation produced: error: request name is required in --no-interactive mode",
    "Manual validation produced: error: request not found: nope; available: get-smart-conditions",
    "bash tests/http-test.sh finished with OK"
  ],
  "residualRisks": [
    "tests/http-oc-test.sh still stops at the pre-existing placeholder assertion until a later task updates that expectation",
    "Request discovery currently loads every YAML file beneath the collection root and will die on invalid YAML in non-request files, matching current loader behavior"
  ],
  "noStagedFiles": true,
  "diffSummary": "Added request discovery/selection helpers and wired main_oc to select a request before hitting the planned environment-resolution placeholder; appended request-selection coverage to the OpenCollection shell test.",
  "reviewFindings": [
    "no blockers"
  ],
  "manualNotes": "Commit created from the isolated worktree only. The report file itself is intentionally uncommitted."
}
```

---

## Task 3 review-fix follow-up (2026-06-24)

Status: DONE

Summary of review fixes:
- Updated `tests/http-oc-test.sh` to expect the Task 3 red-state message `environment resolution is not implemented for request ...` instead of the stale Task 2 request-discovery placeholder.
- Fixed duplicate test numbering in the dedicated OpenCollection shell suite.
- Kept Task 3 intentionally red only at the environment-resolution placeholder and left direct CLI behavior unchanged.

Files changed:
- `tests/http-oc-test.sh`
- `.superpowers/sdd/task-3-report.md`

Exact test commands run and their output:

1. `bash tests/http-oc-test.sh`

```text
test 1: oc parser is available
FAIL: oc should reach the intentional request-discovery placeholder
  expected to find: request discovery is not implemented for collection collectionA
  in:
    error: environment resolution is not implemented for request get-smart-conditions
```

2. `bash tests/http-test.sh`

```text
test 1: simplest post
test 2: get emits no -X
test 3: delete emits -X DELETE
test 4: dedup of leading slash in path
test 5: -i, -k, -L pass through
test 6: -B flag precedence
test 7: HTTP_BASE_URL wins over BASE_URL
test 8: BASE_URL fallback
test 9: no base URL is an error
test 10: -H stacks
test 11: -t bearer
test 12: empty -t is an error
test 13: -t and explicit Authorization
test 14: single -q
test 15: multiple -q
test 16: -q URL-encoding
test 17: -d inline body
test 18: -f with auto Content-Type
test 19: -f .jsonc auto Content-Type
test 20: -f .xml auto Content-Type
test 21: -f other extension -> octet-stream
test 22: explicit -H Content-Type wins
test 23: -f and -d together is an error
test 24: -f with missing file is an error
test 25: -v in -d
test 26: -v in file body
test 27: undefined variable is an error
test 28: -v with empty value
test 29: dry-run output
test 30: dry-run shlex roundtrip
test 31: live execution hits the stub
test 32: .jsonc comments stripped
test 33: .jsonc preserves // in strings
test 34: GET defaults Content-Type to application/json
test 35: explicit Content-Type wins on GET
test 36: GET with -f keeps file-derived Content-Type
OK
```

3. `bash tests/http-oc-test.sh`

```text
test 1: oc parser is available
test 2: missing .httprc is a clear error
test 3: invalid .httprc top-level shape is a clear error
test 4: invalid collection manifest top-level shape is a clear error
test 5: collection fallback directory name
test 6: request name required non-interactive
test 7: unknown request lists available
OK
```

4. `bash tests/http-test.sh`

```text
test 1: simplest post
test 2: get emits no -X
test 3: delete emits -X DELETE
test 4: dedup of leading slash in path
test 5: -i, -k, -L pass through
test 6: -B flag precedence
test 7: HTTP_BASE_URL wins over BASE_URL
test 8: BASE_URL fallback
test 9: no base URL is an error
test 10: -H stacks
test 11: -t bearer
test 12: empty -t is an error
test 13: -t and explicit Authorization
test 14: single -q
test 15: multiple -q
test 16: -q URL-encoding
test 17: -d inline body
test 18: -f with auto Content-Type
test 19: -f .jsonc auto Content-Type
test 20: -f .xml auto Content-Type
test 21: -f other extension -> octet-stream
test 22: explicit -H Content-Type wins
test 23: -f and -d together is an error
test 24: -f with missing file is an error
test 25: -v in -d
test 26: -v in file body
test 27: undefined variable is an error
test 28: -v with empty value
test 29: dry-run output
test 30: dry-run shlex roundtrip
test 31: live execution hits the stub
test 32: .jsonc comments stripped
test 33: .jsonc preserves // in strings
test 34: GET defaults Content-Type to application/json
test 35: explicit Content-Type wins on GET
test 36: GET with -f keeps file-derived Content-Type
OK
```

Self-review findings:
- Scope stayed limited to the two requested review findings.
- The dedicated `http oc` suite now matches the current Task 3 intentional red state and has unique sequential numbering.
- No changes were made to approved spec/plan files or direct CLI behavior.

Concerns:
- None.

---

## Task 3 review fix: ambiguous request coverage (2026-06-24)

Status: DONE

Summary of fix:
- Added dedicated `tests/http-oc-test.sh` coverage for ambiguous request selection in `--no-interactive` mode.
- The new test creates two request YAML files with the same basename and proves the existing `request name is ambiguous:` error path in `general/bin/http` is exercised without changing runtime behavior.
- Kept Task 3 red only at the environment-resolution placeholder for the happy-path request.

Files changed:
- `tests/http-oc-test.sh`
- `.superpowers/sdd/task-3-report.md`

Exact test commands run and their output:

1. `bash tests/http-oc-test.sh`

```text
test 1: oc parser is available
test 2: missing .httprc is a clear error
test 3: invalid .httprc top-level shape is a clear error
test 4: invalid collection manifest top-level shape is a clear error
test 5: collection fallback directory name
test 6: request name required non-interactive
test 7: unknown request lists available
test 8: ambiguous request name is rejected non-interactive
OK
```

2. `bash tests/http-test.sh`

```text
test 1: simplest post
test 2: get emits no -X
test 3: delete emits -X DELETE
test 4: dedup of leading slash in path
test 5: -i, -k, -L pass through
test 6: -B flag precedence
test 7: HTTP_BASE_URL wins over BASE_URL
test 8: BASE_URL fallback
test 9: no base URL is an error
test 10: -H stacks
test 11: -t bearer
test 12: empty -t is an error
test 13: -t and explicit Authorization
test 14: single -q
test 15: multiple -q
test 16: -q URL-encoding
test 17: -d inline body
test 18: -f with auto Content-Type
test 19: -f .jsonc auto Content-Type
test 20: -f .xml auto Content-Type
test 21: -f other extension -> octet-stream
test 22: explicit -H Content-Type wins
test 23: -f and -d together is an error
test 24: -f with missing file is an error
test 25: -v in -d
test 26: -v in file body
test 27: undefined variable is an error
test 28: -v with empty value
test 29: dry-run output
test 30: dry-run shlex roundtrip
test 31: live execution hits the stub
test 32: .jsonc comments stripped
test 33: .jsonc preserves // in strings
test 34: GET defaults Content-Type to application/json
test 35: explicit Content-Type wins on GET
test 36: GET with -f keeps file-derived Content-Type
OK
```

Self-review findings:
- Scope stayed limited to the requested review fix.
- The new coverage targets only the non-interactive ambiguous-selection error path and leaves direct CLI behavior unchanged.
- Happy-path `http oc` remains intentionally red only at environment resolution.

Concerns:
- None.
