# `auth-code-token` — forced reauthentication support design

**Date:** 2026-06-23
**Status:** Awaiting user review of written spec
**Scope:** Extend `general/bin/auth-code-token` so the caller can force a fresh login attempt and inject custom authorization request parameters in an IdP-agnostic way.

---

## 1. Problem Statement

`general/bin/auth-code-token` currently performs a standard OAuth 2.0 Authorization Code + PKCE flow by opening the browser, waiting for the loopback callback, and exchanging the authorization code for tokens.

In practice, when the user invokes the script again shortly after a successful login, the browser and identity provider often reuse the existing session and immediately complete the flow without prompting for credentials again.

That is convenient by default, but sometimes the user explicitly wants to reauthenticate. The script currently has no built-in way to request that behavior.

---

## 2. Goals and Non-Goals

### Goals

- Add a simple CLI flag that requests a fresh authentication prompt.
- Keep the feature generic enough to work across different IdPs.
- Allow callers to append or override extra authorization request parameters when an IdP needs custom behavior.
- Preserve the current default flow when the new options are not used.
- Keep the change local to the authorization request construction path.
- Validate custom parameter input and fail clearly on malformed values.
- Prevent user-supplied overrides of core OAuth/PKCE parameters that are required for correctness and security.

### Non-Goals

- No dedicated logout or end-session flow in this change.
- No provider-specific built-in profiles such as Auth0, Keycloak, Cognito, or Entra presets.
- No guarantee that every IdP will truly force credential entry; the script can only request it via authorization parameters.
- No change to token exchange behavior.
- No persistence of auth parameter presets outside the CLI invocation.

---

## 3. Command Surface

### New flags

Add the following CLI options to `general/bin/auth-code-token`:

- `--force-login`
  - Requests reauthentication by adding standard authorization parameters.
- `--auth-param key=value`
  - Repeatable.
  - Adds a custom query parameter to the authorization URL.
  - May override the default values introduced by `--force-login`.

### Examples

```sh
auth-code-token CLIENT_ID AUTH_URL TOKEN_URL --force-login
```

```sh
auth-code-token CLIENT_ID AUTH_URL TOKEN_URL \
  --force-login \
  --auth-param prompt=login \
  --auth-param acr_values=urn:example:loa:2
```

```sh
auth-code-token CLIENT_ID AUTH_URL TOKEN_URL \
  --auth-param prompt=select_account
```

---

## 4. Chosen Approach

Implement a two-layer mechanism:

1. `--force-login` injects a small set of portable defaults intended to encourage reauthentication.
2. `--auth-param key=value` allows the user to adapt the authorization request for any IdP by adding provider-specific parameters or overriding the defaults.

### Why this approach

- It gives a short, ergonomic path for the common case.
- It stays IdP-agnostic instead of hardcoding vendor semantics.
- It recognizes the reality that OAuth/OIDC providers differ in how they interpret login-related parameters.
- It avoids over-designing a provider abstraction for a single helper script.

### Alternatives considered

1. **Only `--force-login` with hardcoded behavior**
   - Too rigid for cross-provider compatibility.
2. **Only `--auth-param key=value` with no dedicated flag**
   - Maximally generic but less convenient for the main use case.
3. **Add a logout flow**
   - Not generic enough for this iteration because logout endpoints and required parameters vary substantially by provider.

---

## 5. Authorization Request Semantics

### Base request

The script already builds an authorization request containing required flow parameters such as:

- `response_type=code`
- `client_id`
- `redirect_uri`
- `code_challenge`
- `code_challenge_method=S256`
- `state`
- optional `scope`

That behavior remains unchanged.

### `--force-login` defaults

When `--force-login` is present, the script adds these parameters to the authorization request:

- `prompt=login`
- `max_age=0`

These are the most portable defaults for signaling that the provider should prompt again rather than silently reusing the existing browser session.

### `--auth-param` precedence

Each `--auth-param key=value` is applied after the base request and after `--force-login` defaults.

That means the final precedence is:

1. script-required OAuth/PKCE parameters
2. `--force-login` defaults
3. user-supplied `--auth-param` values

This allows the user to:

- override `prompt=login` with something else such as `prompt=select_account`
- override `max_age=0` if needed
- add IdP-specific keys such as `acr_values`, `login_hint`, or `audience`

---

## 6. Protected Parameters

To avoid breaking the flow or weakening safeguards, `--auth-param` must **not** be allowed to override parameters that are essential to the script’s correctness or security.

The protected set should include:

- `response_type`
- `client_id`
- `redirect_uri`
- `code_challenge`
- `code_challenge_method`
- `state`

If the user attempts to set any protected key via `--auth-param`, the script should exit with a clear error.

### Why protect these keys

- They are generated or controlled by the script as part of the PKCE flow.
- Allowing overrides could cause invalid requests, callback mismatch, or state validation problems.
- They are not legitimate extension points for the stated user need.

Notably, `scope` remains governed by the existing `--scope` option and should also stay under the script’s own control rather than being duplicated through `--auth-param`.

---

## 7. Input Validation and Errors

### `--auth-param` format

Each `--auth-param` value must be in `key=value` form.

Validation rules:

- the string must contain `=`
- the key must be non-empty
- the value may be empty only if the implementation intentionally chooses to allow it; for this change, the safer default is to allow empty values only if explicitly present as `key=`

### Error cases

| Condition | Expected behavior |
| --- | --- |
| `--auth-param` without `=` | exit with clear error, e.g. `Error: --auth-param must use key=value format` |
| empty key such as `=value` | exit with clear error |
| protected parameter override | exit with clear error naming the forbidden key |
| repeated custom key | last value wins |

### Repeated keys

For unprotected keys, repeated `--auth-param` occurrences should be resolved by straightforward override semantics, where the last provided value wins. This matches the existing mental model of CLI option precedence and keeps the request deterministic.

---

## 8. Implementation Shape

The change should stay small and localized to the existing Python script.

### Likely code structure

Add:

- new argparse definitions for `--force-login` and repeatable `--auth-param`
- a helper to parse and validate custom auth parameters
- a small protected-key set
- logic to merge base params, force-login defaults, and custom params before URL encoding

Suggested helper responsibilities:

1. parse raw `key=value` strings into a dictionary
2. validate malformed entries
3. reject protected keys
4. return merged custom values for the authorization request

The rest of the script flow — browser launch, callback server, state validation, and token exchange — should remain unchanged.

---

## 9. Testing Strategy

This change is well suited to focused automated tests around argument parsing and authorization URL construction.

### Test coverage targets

- `--force-login` adds `prompt=login` and `max_age=0`
- `--auth-param` can be specified multiple times
- `--auth-param` rejects malformed `key=value` input
- custom params override `--force-login` defaults
- custom params append new provider-specific values
- protected keys are rejected with a clear error
- behavior without the new flags remains unchanged

### Test level

Prefer unit-style tests around argument parsing and URL construction helpers, rather than full browser/callback integration tests, because the behavior being added is deterministic and isolated.

---

## 10. Success Criteria

The work is successful when:

- `auth-code-token` accepts `--force-login`
- `auth-code-token` accepts repeatable `--auth-param key=value`
- `--force-login` adds `prompt=login` and `max_age=0` to the authorization request
- `--auth-param` can override those defaults and add arbitrary extra request parameters
- protected OAuth/PKCE parameters cannot be overridden
- malformed custom parameter input fails clearly
- existing behavior is unchanged when the new options are not used

---

## 11. Design Summary

Extend `general/bin/auth-code-token` with a portable forced-login mechanism by introducing `--force-login` and repeatable `--auth-param key=value`. `--force-login` adds `prompt=login` and `max_age=0`, while `--auth-param` provides the IdP-specific escape hatch needed for real-world compatibility. The script continues to own all critical OAuth/PKCE parameters and rejects unsafe overrides.
