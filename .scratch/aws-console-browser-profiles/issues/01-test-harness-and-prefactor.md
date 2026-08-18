# 01 — Test harness & prefactor (foundation)

**What to build:** Today's script behavior becomes verifiable offline: a bash harness (in the style of the repo's existing sibling-script harness) runs the real script as a subprocess with AWS, federation, and browser stubbed at the process boundary via environment — so `aws-console`, `--profile`, and `--stdout` behave exactly as they do today, with zero network and zero real credentials. Internally the script is reorganized into pure helpers (binding sanitization, URL building, browser resolution, destination building) plus thin IO wrappers, and the federation endpoint base URL becomes overridable via an environment variable defaulting to the URL hardcoded today. No user-visible behavior changes.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [x] Harness runs the real script offline: STS stubbed through the botocore per-service endpoint variable against a local HTTP stub answering the canonical GetCallerIdentity XML; federation stubbed through the new endpoint override env var against a local HTTP stub answering a SigninToken JSON payload; browser stubbed with a fake script that records its argv.
- [x] Bare `aws-console` opens the signin URL through the platform's default browser (fake browser receives the URL) — today's behavior, unchanged.
- [x] `aws-console --profile <name>` passes the AWS profile through to credential resolution exactly as today.
- [x] `--stdout` prints only the signin URL on stdout.
- [x] The federation endpoint override is read from an environment variable that defaults to today's hardcoded URL.
- [x] Pure helpers are importable so the harness can assert on them directly.
- [x] The script remains a plain executable with the shebang unchanged.

## Comments

- Implemented in `general/bin/aws-console` (prefactor) and `general/bin/aws-console.test` (harness, in the style of `ecs-logs.test`).
- Prefactor: the script is now a set of importable pure helpers (`federation_endpoint`, `build_destination`, `build_get_signin_token_url`, `build_login_url`) plus thin IO wrappers (`fetch_signin_token`, `open_console`). The federation endpoint comes from `AWS_CONSOLE_FEDERATION_ENDPOINT`, defaulting to `https://signin.aws.amazon.com/federation` — the URL hardcoded before. URL construction is byte-identical to the old code with the default endpoint; the shebang (`#!python`) and the CLI contract are unchanged.
- Harness: runs the real script as a subprocess (via `python3`, since the `#!python` shebang resolves on macOS but not on Linux) with one local HTTP stub serving both STS (canonical GetCallerIdentity XML) and federation (SigninToken JSON), and a fake browser recording its argv through the `BROWSER` env var. Covers: bare default-browser open with env credentials, `--profile` pass-through (asserted via the SigV4 access key in the STS stub's request log), `--stdout` URL-only with no browser launch, the executable/shebang properties, and direct assertions on the imported pure helpers (endpoint default/override, destination, token URL, login URL). Run with `general/bin/aws-console.test` — zero network, zero real credentials.
- Verification: harness passes 5/5 runs; full repo test suite green except the pre-existing `tests/herdr-notification-target-test.sh` failure (fails on the pristine tree too); `ruff check` clean; shellcheck clean.
