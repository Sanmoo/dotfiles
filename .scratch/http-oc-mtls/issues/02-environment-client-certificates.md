# 02 — Client certificates per environment with precedence

**What to build:** client certificates declared under `config.environments[].clientCertificates` participate in the same domain-matched selection as the collection manifest's `config.clientCertificates`. The two lists are merged with the environment winning per `domain` — the same precedence direction variables use. Environment entries can reference the selected environment's own variables, and a collection certificate still applies when the environment defines no entry for that domain.

**Blocked by:** 01 — Manifest client certificates reach the main request.

**Status:** ready-for-agent

- [x] A certificate declared only in the environment is matched and presented when that environment is selected
- [x] For the same `domain` in both lists, the environment entry wins when that environment is selected
- [x] A collection-level certificate still applies when the selected environment defines no entry for its `domain`
- [x] Environment entries resolve variables from the full resolved context (collection, request, environment, CLI), including the environment's own variables
- [x] A `disabled` environment entry is skipped and does not mask the collection entry for the same domain
- [x] The merged selection is covered at the process boundary: dry-run shows the environment certificate when it wins and the collection certificate when it is the only match

## Comments

- Implemented in `general/bin/http`; asserted in `tests/http-oc-test.sh` (tests 66–72).
- Integration in `main_oc`: reads both lists (`config.clientCertificates` and the selected environment's `clientCertificates`), validates every non-disabled entry of both lists up front with `validate_client_cert_entry`, merges with `merge_client_certificates` (environment winning per templated, case-folded domain), then the existing `select_oc_client_cert` first-match-wins scan picks the certificate. Both the executed run and the dry-run go through `build_curl_args`, so they always agree.
- Merge semantics: the environment entry for a domain replaces the collection entry in place; environment-only domains are appended in environment order; `disabled` environment entries claim nothing and never mask the collection entry. Domains are compared already templated (with the same resolved variable context, which includes the environment's own variables) and folded case-insensitively, mirroring `domain_matches_host`.
- New helpers: `get_environment_client_certificates` (reads the environment list; shares the list-shape check via `_client_cert_entries`), `validate_client_cert_entry` (host-independent field/type validation, extracted from and reused by `resolve_client_cert_entry`), `templated_cert_domain` (shared domain templating), and `merge_client_certificates` (pure merge).
- Validation stays global, as issue 01 codified: a malformed collection entry masked by an environment override still fails with exit 2 before anything is sent (test 72), and an unselected environment contributes nothing (test 66).
- Only the selected environment participates; issue-03 CLI overrides and issue-04 OAuth2 matching are separate tickets.
