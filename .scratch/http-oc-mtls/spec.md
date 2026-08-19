# http oc: mTLS client certificates (OpenCollection clientCertificates)

Status: ready-for-agent

## Problem Statement

`http oc` cannot reach endpoints that require mutual TLS: there is no way to configure a client certificate anywhere in the tool. A developer whose API demands a client certificate has to abandon the collection, hand-roll the curl command with `--cert`/`--key`, and lose everything `http oc` gives them (variable resolution, auth, the Comando equivalente). The OpenCollection spec already defines client-certificate configuration, and this tool already follows the spec's vocabulary elsewhere — but the feature is simply not implemented.

## Solution

Implement client certificates following the OpenCollection 1.0.0 spec: PEM client certificates declared in the collection manifest (`config.clientCertificates`) and per environment (`config.environments[].clientCertificates`), matched by the request URL's host through the entry's `domain` field (wildcard `*` allowed). The matched certificate is passed to curl as `--cert`/`--key` (plus `--pass` when a `passphrase` is set). CLI flags `--cert`/`--key`/`--cacert` on the `oc` subcommand override the manifest selection for one run. Certificate selection applies both to the request being run and to the OAuth2 token requests, matched by each URL's own host. Requests whose host matches no entry behave exactly as today.

## User Stories

1. As a developer, I want to declare a client certificate in the collection manifest under `config.clientCertificates`, so that every request whose host matches its `domain` presents it.
2. As a developer, I want to declare client certificates inside an environment under `config.environments[].clientCertificates`, so that different environments can use different certificates.
3. As a developer, I want an environment certificate to win over a collection certificate for the same `domain`, so that environments override defaults exactly like variables do.
4. As a developer, I want certificates matched by the request URL's host, so that one collection can talk to several hosts, each with its own certificate, without any per-request wiring.
5. As a developer, I want `*.example.com` to match any subdomain (`api.example.com`, `a.b.example.com`), so that one entry covers a whole host family.
6. As a developer, I want `*.example.com` NOT to match `example.com` itself, so that wildcards mean subdomains only.
7. As a developer, I want `api.example.com` NOT to match `api.example.com.evil.com`, so that a certificate is never sent to a host that merely shares a prefix.
8. As a developer, I want non-`https` URLs to never match a certificate, so that no client identity is attached to plaintext requests.
9. As a developer, I want `disabled: true` entries to be skipped, so that I can keep a certificate configured but inactive.
10. As a developer, I want `type: pem` with `certificateFilePath` and `privateKeyFilePath` to become curl `--cert` and `--key`, so that curl presents the client identity to the server.
11. As a developer, I want a `passphrase` on the entry to become curl `--pass`, so that encrypted private keys work.
12. As a developer, I want a missing cert or key file to fail with exit 2 and a clear `file not found` message before anything is sent, so that config mistakes are caught up front.
13. As a developer, I want a `pkcs12` entry to fail with a clear "not supported" message and exit 2, so that unsupported configs fail loudly instead of being silently ignored.
14. As a developer, I want an entry missing `domain`, `type`, `certificateFilePath`, or `privateKeyFilePath` to fail with a clear error and exit 2, so that malformed manifests are diagnosed immediately.
15. As a developer, I want relative certificate paths resolved against the collection root, so that the collection stays self-contained and movable.
16. As a developer, I want `domain`, `certificateFilePath`, and `privateKeyFilePath` to support `{{var}}` templating (collection, request, environment, and CLI variables) and `{{process.env.X}}`, plus `~` and `$VAR` expansion on paths, so that certificates can live outside the repo and vary per machine or environment.
17. As a developer, I want the first matching entry in the merged list to win, so that ordering is predictable and documented.
18. As a developer, I want requests whose host matches no entry to behave exactly as today (no cert flags at all), so that existing collections are untouched.
19. As a developer, I want CLI `--cert`/`--key` on `http oc` to override the matched manifest certificate for this run, so that I can test a different certificate without editing the collection.
20. As a developer, I want `--cert` without `--key` (or vice versa) to fail with exit 2, so that the pairing mistake is caught before curl.
21. As a developer, I want CLI `--cacert` as an escape hatch to trust a private CA, so that I can verify a self-signed server without any manifest change.
22. As a developer, I want `-k` together with `--cacert` to fail with exit 2 and a clear message, so that contradictory verification flags are caught before curl errors.
23. As a developer, I want `-k` together with a client certificate (cert+key, no `--cacert`) to work, so that a self-signed server requiring a client cert is reachable with cert+key only.
24. As a developer, I want the same domain matching applied to OAuth2 token requests, so that a token endpoint requiring mTLS works without extra configuration.
25. As a developer, I want the token cache to keep working unchanged when certificates are configured, so that no extra token fetches happen (and `--auth-no-cache` still forces a refetch when a certificate changes).
26. As a developer, I want the dry-run to print the curl command including `--cert`/`--key`/`--pass` from the matched certificate, so that I can verify the selection before sending.
27. As an interactive user, I want the Comando equivalente to reproduce a manifest-matched certificate for free (it comes from the collection/environment selection), and to include `--cert`/`--key`/`--cacert` when I passed them on the command line, so that every run stays reproducible.
28. As a developer, I want request documents to carry no TLS configuration at all, so that our collections stay aligned with the OpenCollection spec (certificates belong to collection/environment config).

## Implementation Decisions

- The format follows the OpenCollection 1.0.0 spec's client-certificate schema: `config.clientCertificates` (collection) and `config.environments[].clientCertificates` (environment). Only the `pem` entry shape is implemented; `pkcs12` fails with a clear error.
- A certificate entry has `domain`, `type` (`pem`), `certificateFilePath`, `privateKeyFilePath`, optional `passphrase`, and optional `disabled`. Missing required fields fail with exit 2.
- Selection: collection and environment lists are merged, with the environment winning per `domain` (the same precedence direction variables use). The selected request/environment variables are resolved before certificates, so certificate fields can reference them.
- Matching: only `https` URLs participate. The host matches `domain` exactly, or, when the domain starts with `*`, the rest of the domain matches as a host suffix (`*.example.com` matches `api.example.com` but not `example.com`). Matching is anchored at the host end — a domain never matches a longer host that merely shares a prefix. This deliberately fixes the unanchored prefix match of the spec's reference implementation, which could send a certificate to an unrelated host.
- The first matching entry wins; `disabled` entries are skipped.
- All string fields of an entry (`domain`, paths, `passphrase`) go through the existing variable templating and process-env expansion; certificate paths additionally expand `~` and `$VAR` and resolve relative to the collection root (the manifest's directory).
- curl mapping: `certificateFilePath` → `--cert`, `privateKeyFilePath` → `--key`, `passphrase` → `--pass`.
- CLI: the `oc` subcommand gains `--cert`, `--key`, and `--cacert`. `--cert`/`--key` must be provided together (exit 2 otherwise); when present they replace the manifest-matched certificate for the main request. `--cacert` applies to the main request and is mutually exclusive with `-k` (exit 2). CLI certificates are NOT applied to token requests — token requests are matched against the manifest lists by their own host.
- The same domain matching runs for OAuth2 token requests (`client_credentials` and `authorization_code`), each against its own URL's host.
- The token cache key is unchanged; rotating a certificate requires `--auth-no-cache` to force a refetch.
- Certificate file existence is validated at build time with a clear `file not found` message and exit 2, before any curl invocation (same behavior as the existing body file handling).
- Selection happens before the curl arguments are built; the matched certificate flows through the existing curl-argument builder, so dry-run and execution always agree.
- The Comando equivalente builder needs no change for manifest-sourced certificates (collection + environment selection reproduces them); the CLI certificate flags are appended to the equivalent command when used.

## Testing Decisions

A good test asserts **external behavior only**: the printed curl command (dry-run), the curl args received by the stub (including token-request invocations), stderr messages, and exit codes — never internal data structures.

Two existing seams, already used by the current `oc` tests:

1. **Process boundary (primary, highest seam)** — run `http oc` as a subprocess with a stub `curl` on `PATH` and a temp `HOME` whose `.httprc` points at a temp collection; assert on stdout, stderr, exit code, and the stub's captured arguments. Covers matching (exact, wildcard, subdomain-negative, prefix-anchor-negative, http-negative), precedence, `disabled`, passphrase, pkcs12/required-field/file-missing errors, CLI overrides and pairing errors, `-k`×`--cacert`, dry-run output, and cert flags on token requests.
2. **Module boundary (secondary)** — import the `http` module and unit-test pure builders: the Comando equivalente builder for the inclusion of `--cert`/`--key`/`--cacert`, and the new pure domain-matching helper (the decision-rich rules: wildcard, anchoring, https-only). Prior art: the existing unit tests of the equivalent-command builder for `-v`, `--dqwnp`, and the body override.

## Out of Scope

- `pkcs12` certificate entries (clear error only).
- `ca` as a manifest field — server-side trust is configured via CLI `--cacert` only.
- mTLS on the shared REST subcommands (`http get`/`post`/`put`/`patch`/`delete`) — `oc` only.
- Certificate type flags (`--cert-type`/`--key-type`).
- Per-request TLS blocks — the spec does not define them.
- Passing `-k` to OAuth2 token requests (unchanged behavior).
- Token cache-key changes.

## Further Notes

- The original design idea was a per-request `tls` block; the OpenCollection spec defines collection/environment-level `clientCertificates` matched by domain, and the project's rule is to follow the spec. The final shape is therefore spec-compliant. (No ADR was requested.)
- The matching semantics fix the reference implementation's unanchored prefix match on purpose: with curl, a mis-matched certificate is a credential sent to the wrong host.
- Domain terminology (`clientCertificates`, `domain`, `certificateFilePath`, `privateKeyFilePath`, `passphrase`, `disabled`) follows the spec verbatim and is already captured in the project glossary (`CONTEXT.md`).
