# 01 — Manifest client certificates reach the main request

**What to build:** a client certificate declared in the collection manifest under `config.clientCertificates` is matched to the request by its URL host and presented by curl on the main request. A `pem` entry with `domain`, `certificateFilePath`, and `privateKeyFilePath` (optional `passphrase`, `disabled`) becomes `--cert`/`--key`/`--pass` in the executed and dry-run curl commands. Matching is https-only, exact host or `*` wildcard as host suffix, anchored at the host end, first match wins, `disabled` skipped. Entry fields are templated (`{{var}}`, `{{process.env.X}}`); certificate paths also expand `~`/`$VAR` and resolve relative to the collection root. Malformed entries, `pkcs12`, and missing certificate files fail with exit 2 and a clear message before anything is sent.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [x] A collection with a matching `pem` entry makes the main request's curl receive `--cert` and `--key` (and `--pass` when `passphrase` is set)
- [x] The dry-run command shows the same certificate flags
- [x] Exact domain match applies the certificate; a host that merely shares a prefix with the domain does not receive it
- [x] `*.example.com` matches subdomains but not `example.com` itself; non-`https` URLs never match
- [x] First matching entry wins; `disabled: true` entries are skipped
- [x] `domain` and certificate paths resolve `{{var}}`/`{{process.env.X}}`; paths expand `~`/`$VAR` and resolve relative to the collection root
- [x] An entry missing `domain`, `type`, `certificateFilePath`, or `privateKeyFilePath` exits 2 naming the missing field
- [x] A `pkcs12` entry exits 2 with a clear "not supported" message
- [x] A missing certificate or key file exits 2 with a clear `file not found` message before any request is made
- [x] A request whose host matches no entry behaves exactly as today (no certificate flags)
- [x] Domain matching is covered by module-boundary unit tests for the pure matching rules

## Comments

- Implemented in `general/bin/http`; all user-visible behavior asserted in `tests/http-oc-test.sh` (tests 54–64).
- Selection flow: `main_oc` resolves variables → `build_basic_oc_args` (URL) → `select_oc_client_cert` (validates + templates entries, matches by https host) → attaches `cert`/`key`/`passphrase` to the direct args, which `build_curl_args` turns into `--cert`/`--key`/`--pass`. Both the executed run and the dry-run go through `build_curl_args`, so they always agree; unmatched hosts yield no flags (behavior unchanged).
- New helpers: `get_manifest_client_certificates` (reads `config.clientCertificates`), `domain_matches_host` (pure matching rule), `resolve_client_cert_entry` (validation/templating/file checks), `request_url_https_host` (https-only), `select_oc_client_cert` (first-match-wins scan).
- Semantics: `disabled: true` is skipped before any other validation; every other entry is validated (missing required field / non-`pem` type incl. `pkcs12`) and fails with exit 2 before anything is sent — even when the request is not https or its host matches nothing. Only a matched https entry gets its certificate/key **file existence** checked (so an unrelated host's machine-specific config does not break requests), before anything is sent (build is ahead of the token request). Matching is exact or `*.`-wildcard-as-host-suffix, anchored at the host end (a dot-less `*example.com` never crosses a label boundary), https-only, case-insensitive.
- Path handling: templating via the existing `apply_template` (which also handles `{{process.env.X}}`), then `~`/`$VAR` expansion, then relative paths resolve against the collection root.
- Tests: process-boundary seams 54–62 (execute + dry-run flags, exact/prefix-anchor/wildcard/apex/https negatives, first-match-wins, disabled skip, templating + `~`/`$VAR`/`{{process.env.X}}` + relative resolution, missing-field/pkcs12/file-not-found errors, unmatched-host passthrough); module-boundary unit tests 63–64 for `domain_matches_host` and `request_url_https_host`.
- Only the collection-level (`config.clientCertificates`) list is wired to the main request, per this ticket; environment precedence, CLI overrides, and OAuth2 token matching are separate tickets (02–04).
