# 04 — Client certificates on OAuth2 token requests

**What to build:** the OAuth2 token requests (`client_credentials` and `authorization_code`) receive the client certificate matched by their own `tokenUrl` host, using the merged collection/environment certificate lists. A token endpoint whose host matches an entry gets `--cert`/`--key`/`--pass` on the token call; a host matching nothing keeps today's behaviour. The token cache is unchanged: cached tokens skip the curl call entirely, and `--auth-no-cache` still forces a refetch.

**Blocked by:** 02 — Client certificates per environment with precedence.

**Status:** resolved

- [x] A `client_credentials` token call to a host matching a certificate entry receives the certificate flags
- [x] An `authorization_code` token call to a host matching a certificate entry receives the certificate flags
- [x] A token host matching no entry produces no certificate flags (behaviour unchanged)
- [x] Environment-level certificates apply to token matching the same way they apply to the main request
- [x] A cached token skips the token curl call entirely, with or without certificates configured
- [x] `--auth-no-cache` refetches and applies the matching certificate on the refetch
- [x] Token-call certificate flags are covered at the process boundary (stub curl capturing the token invocation)

## Comments

- Implemented in `general/bin/http` and `general/bin/auth-code-token`; asserted in `tests/http-oc-test.sh` (tests 80–86).
- `main_oc` now hoists the merged certificate list (`merge_client_certificates(manifest, environment, oc_variables)`) into `merged_certs` and passes it — with the collection path and the same variable context the main-request selection uses (`oc_variables`) — into `resolve_oauth2_token`.
- Selection in `resolve_oauth2_token` runs against the **templated** `tokenUrl`'s own https host via the existing `select_oc_client_cert` (so domains, wildcards, https-only, and env-wins-per-domain semantics are identical to the main request), and only after the cache lookup: a cache hit returns before any certificate is looked up, so a cached token skips the token curl call entirely and no `file not found` fires for it. `--auth-no-cache` skips the cache, so the refetch selects and applies the certificate.
- `_token_cert_flags(matched_cert)` flattens a matched entry into `--cert/--key` (plus `--pass` when a passphrase is set), mirroring the main request's curl mapping. `run_client_credentials` appends these flags to its curl command; `run_authorization_code` appends them to the `auth-code-token` helper invocation (as `--cert/--key/--pass`). CLI `--cert/--key` still never reach token calls — token matching stays purely manifest/environment-sourced (test 85's tail re-asserts this with a manifest cert that matches the token host).
- `auth-code-token` gains `--cert`/`--key`/`--pass`: `build_ssl_context` loads the PEM cert chain onto `ssl.create_default_context()` (standard CA verification preserved; encrypted keys via `load_cert_chain(..., password=...)` need Python 3.13+) and `post_form` passes the context to `urlopen`. Pairing is enforced before any auth flow (exit 1, clear message): `--cert`/`--key` must be provided together, and `--pass` requires `--cert`/`--key`. The real mTLS path was verified end-to-end against a local `CERT_REQUIRED` HTTPS server: a request without the client cert is rejected, and with the cert the token exchange succeeds.
- Tests: process-boundary 80 (client_credentials token call receives `--cert/--key/--pass`, main request unaffected, templated `tokenUrl` resolved before matching), 81 (authorization_code helper receives the flags; refetch via `--auth-no-cache` keeps them and still forces login), 82 (token host matching nothing gets no flags while the main request still gets its own), 83 (environment-level certs apply to token matching; an environment without certs produces none), 84 (cached token skips the token curl call with certs configured; `--auth-no-cache` refetches and applies the matching cert), 85 (missing token-cert file exits 2 with `file not found` before any token curl; CLI certs still never leak into the token call) and its tail (manifest cert applied to the token call even when CLI `--cert/--key` are passed); module-boundary unit test 86 for `_token_cert_flags` (None/absent/empty passphrase shapes) plus a real-helper smoke test asserting `--cert`-alone, `--key`-alone, and `--pass`-alone pairing errors exit 1 before any auth flow.
