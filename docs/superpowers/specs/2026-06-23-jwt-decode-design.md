# `jwt-decode` — JWT payload decoder CLI design

**Date:** 2026-06-23
**Status:** Awaiting user review of written spec
**Scope:** A small shell script in `general/bin/` that accepts a JWT as a positional argument, decodes its payload, and prints formatted JSON with `jq`.

---

## 1. Problem Statement

When inspecting OAuth or API tokens, it is common to quickly check the JWT payload to see claims such as `sub`, `scope`, `aud`, and `exp`.

Today that requires repeating a fragile one-off command that:

- splits the token on `.`,
- decodes the second segment using base64url rules,
- and pipes the result into `jq` for readable output.

A small reusable CLI should make this a one-command operation from the existing dotfiles toolset.

---

## 2. Goals and Non-Goals

### Goals

- Add a new executable script at `general/bin/jwt-decode`.
- Accept the JWT as a single positional argument.
- Decode the **payload** segment (the second JWT part).
- Support base64url input used by JWTs (`-`/`_`, optional missing padding).
- Print pretty JSON using `jq`.
- Fail with clear error messages for invalid usage or malformed tokens.
- Stay small and dependency-light, aligned with the existing `general/bin` scripts.

### Non-Goals

- No stdin support in v1.
- No signature verification.
- No header decoding output in v1.
- No claim validation (`exp`, `iss`, `aud`, etc.).
- No support for JWE or encrypted tokens.

---

## 3. Command Surface

### Invocation

```sh
jwt-decode <token>
```

### Behavior

- If exactly one argument is not provided, print usage to stderr and exit 1.
- If `jq` or `base64` is unavailable, print an explicit dependency error and exit 1.
- If the token does not contain at least two `.`-separated segments, print an invalid-token error and exit 1.
- Decode the second segment using base64url normalization:
  - replace `-` with `+`
  - replace `_` with `/`
  - add `=` padding until the length is a multiple of 4
- Pipe the decoded payload into `jq` so the output is formatted JSON.
- If decoding fails or the decoded payload is not valid JSON, exit non-zero with a clear error.

### Example

```sh
jwt-decode eyJhbGciOi...eyJzdWIiOiIxMjMifQ.signature
```

Output:

```json
{
  "sub": "123"
}
```

---

## 4. Chosen Approach

Use a short **bash** script with `jq` and `base64`.

Why this approach:

- It matches the style of small helper scripts already present in `general/bin/`.
- It keeps the implementation short and easy to tweak locally.
- The only non-trivial part is base64url normalization, which is still manageable in shell for this scope.

Alternatives considered:

1. **Python script** — more robust parsing, but more verbose than needed for this simple helper.
2. **Ultra-short shell one-liner wrapper** — shorter, but harder to read and maintain.

---

## 5. Implementation Shape

### File Layout

```text
general/bin/jwt-decode
```

No additional production files are required.

### Script Structure

The script should remain linear and minimal:

1. validate argument count;
2. validate required commands;
3. extract payload segment;
4. normalize base64url to standard base64;
5. add padding;
6. decode;
7. pretty-print with `jq`.

### Dependency Assumptions

- `jq` must be installed.
- `base64` must be installed.
- The repo already distributes executable helpers through the `general` stow package.

---

## 6. Error Handling

Expected error cases:

| Condition | Message style | Exit |
| --- | --- | --- |
| Wrong arg count | `Usage: jwt-decode <token>` | 1 |
| Missing `jq` | `Error: required command 'jq' not found` | 1 |
| Missing `base64` | `Error: required command 'base64' not found` | 1 |
| Token missing payload segment | `Error: invalid JWT` | 1 |
| Base64 decode failure | `Error: failed to decode JWT payload` | 1 |
| Payload not valid JSON | rely on `jq` parse failure; wrap with `Error: invalid JWT payload JSON` if needed | 1 |

The script should avoid silently printing partial or invalid output.

---

## 7. Validation Plan

### Static / smoke checks

- Ensure the script is executable.
- Run the script against a known JWT and confirm formatted JSON output.
- Run the script with no args and confirm the usage message.
- Run the script with malformed input and confirm a clean failure.

### Automated test shape

Add a shell test, following the repository pattern used by other helper scripts, covering at least:

1. successful payload decode;
2. wrong number of arguments;
3. malformed token;
4. invalid base64 or invalid JSON payload.

---

## 8. Success Criteria

The work is successful when:

- `general/bin/jwt-decode` exists and is executable;
- `jwt-decode <token>` prints the decoded JWT payload as formatted JSON;
- malformed tokens fail clearly;
- the implementation stays small and consistent with the other scripts in `general/bin/`;
- automated checks for the new helper pass.

---

## 9. Chosen Design Summary

Implement `jwt-decode` as a small bash script in `general/bin/` that accepts one positional JWT, decodes only the payload segment with proper base64url handling, and formats the result with `jq`. The tool intentionally does not verify signatures or support stdin in v1.
