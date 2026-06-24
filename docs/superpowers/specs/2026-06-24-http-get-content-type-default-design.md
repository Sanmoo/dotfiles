# `http get` default Content-Type design

**Date:** 2026-06-24  
**Status:** Awaiting user review of written spec  
**Scope:** Narrow follow-up to `docs/superpowers/specs/2026-06-18-http-cli-design.md` for `general/bin/http`.

---

## 1. Problem Statement

`general/bin/http` already supports a convenient `http get ...` subcommand and auto-adds `Content-Type` for file-backed request bodies (`-f`).

The missing ergonomic piece is that plain GET requests still require the user to remember `-H "Content-Type: application/json"` even when JSON is the default payload contract for the API being queried.

We want GET requests to be friendlier without changing the explicit-header escape hatch:

- `http get` should default to `Content-Type: application/json` when no more specific auto Content-Type has already been chosen.
- If the user supplies any explicit `Content-Type` header, that explicit value wins.
- Existing `-f` content-type inference must continue to work and must not stack a second auto header on top of the GET default.

---

## 2. Goals and Non-Goals

### Goals

- Add a default `Content-Type: application/json` for `http get` requests that do not already have a more specific auto `Content-Type` from `-f`.
- Keep the default conditional on the absence of an explicit `Content-Type` header.
- Preserve the current precedence where `-f` still wins over the GET default when no explicit header is provided.
- Preserve the current `-f` behavior for file-backed request bodies.
- Keep the change small and localized to `general/bin/http` and its shell tests.

### Non-Goals

- No new flags.
- No change to base URL resolution.
- No change to `POST` / `PUT` / `PATCH` / `DELETE` behavior beyond the shared Content-Type resolution logic needed to avoid duplicate auto headers.
- No `Accept` header default.
- No config file or environment variable for overriding the new GET default.

---

## 3. Proposed Behavior

### 3.1 Content-Type precedence

The request should have **at most one auto-generated `Content-Type` header**. Resolution order:

1. **Explicit header wins**: if the user passed `-H "Content-Type: ..."` (any case variant), do not add any default.
2. **File-backed body wins next**: if `-f` is used and no explicit `Content-Type` exists, keep the existing extension-based inference (`application/json`, `application/xml`, or `application/octet-stream`).
3. **GET default last**: if the method is `get`, no explicit `Content-Type` exists, and no `-f`-derived type is already selected, add `Content-Type: application/json`.

This keeps the new GET default from duplicating or overriding the file-body behavior.

### 3.2 Cases

| Invocation shape | Result |
| --- | --- |
| `http get -B ... foo` | adds `Content-Type: application/json` |
| `http get -B ... -H "Content-Type: text/plain" foo` | keeps explicit `text/plain`, adds nothing else |
| `http get -B ... -f payload.json foo` | keeps the existing file-derived `application/json` |
| `http get -B ... -f payload.xml foo` | keeps the existing file-derived `application/xml` |
| `http post -B ... -f payload.json foo` | unchanged current behavior |
| any method with `-H "Content-Type: ..."` | explicit header suppresses all auto Content-Type defaults |

---

## 4. Implementation Shape

### 4.1 Code path

`general/bin/http` should centralize Content-Type resolution so the GET default and the file-body default use the same decision point.

A small helper is enough, for example:

- `has_header(headers, "Content-Type")` or similar case-insensitive check
- `resolve_auto_content_type(args)` returning either a single auto header value or `None`

`build_curl_args(...)` then emits only the resolved auto header, if any.

### 4.2 Why centralize it

The current script already has one Content-Type decision for `-f`. Adding a second GET-only decision inline would risk duplicate headers in mixed cases. Centralizing the logic keeps the behavior explicit and makes the test surface smaller.

### 4.3 No CLI surface changes

The script continues to expose the same subcommands and flags. The only observable change is the new default header on GET when no explicit Content-Type is present.

---

## 5. Test Plan

Extend `tests/http-test.sh` with shell-level regression coverage using the existing stub-`curl` approach.

### New or updated cases

1. **GET default header**
   - `http get -B https://api.example.com foo`
   - Assert the emitted curl args contain `Content-Type: application/json`.

2. **GET respects explicit header**
   - `http get -B https://api.example.com -H "Content-Type: text/plain" foo`
   - Assert only the explicit `Content-Type` is present and the JSON default is absent.

3. **GET with `-f` keeps file-derived type**
   - `http get -B https://api.example.com -f payload.xml foo`
   - Assert `Content-Type: application/xml` is emitted and no JSON default is added.

4. **Existing file-body regression remains**
   - Keep the current `-f` tests that verify explicit `-H "Content-Type: ..."` suppresses auto inference.

No network I/O is required; all tests stay local and deterministic.

---

## 6. Acceptance Criteria

The change is complete when:

- `http get` emits `Content-Type: application/json` by default.
- Any explicit `Content-Type` header suppresses the default.
- `-f` continues to use its current inference rules and does not produce duplicate auto `Content-Type` headers.
- The updated `tests/http-test.sh` passes.
- Existing non-GET behavior remains unchanged.
