# 02 — Browser profile isolation

**What to build:** `aws-console --profile <name>` (with `<name>` ≠ `default`) opens the federated signin URL in a dedicated browser profile derived from the binding rule `aws-<sanitized name>`, launched by directly executing the resolved per-OS browser binary (Linux: google-chrome-stable; macOS: the Microsoft Edge app-bundle binary) with the profile-directory flag, so each AWS profile keeps its own console session and multiple accounts can stay logged in simultaneously. The binding is announced on stderr. A missing binary, or an override that does not look Chromium-family, warns and falls back to the default browser without failing. Bare `aws-console` and `--profile default` keep today's behavior (main browser profile), and the environment override takes precedence over the per-OS defaults. The browser profile is created automatically by the browser on first use.

**Blocked by:** 01 — Test harness & prefactor (foundation)

**Status:** resolved

- [x] `aws-console --profile rev-qual` launches the resolved browser with the profile-directory flag set to `aws-rev-qual` and the signin URL as argument (harness asserts the fake browser's argv).
- [x] The launch is announced on stderr naming the browser profile binding.
- [x] Binding sanitization: characters outside `[A-Za-z0-9._-]` in the AWS profile name are replaced with `-`.
- [x] Bare `aws-console` and `--profile default` take the default-browser path — no isolation, exactly today's behavior.
- [x] The browser override environment variable (name or full path) takes precedence over per-OS defaults.
- [x] A missing browser binary, or a resolved browser not suggesting Chromium-family, prints a warning to stderr, falls back to the default browser, and exits successfully.
- [x] Per-OS browser resolution is covered by direct assertions on the pure resolver (Linux resolves chrome-stable, macOS resolves the Edge bundle binary), since the harness runs on a single host OS.
- [x] `--stdout` combined with an isolated profile keeps stdout URL-only and reports the binding on stderr.

## Comments

Implemented in `general/bin/aws-console` (commit 063be50). The offline harness
in `general/bin/aws-console.test` asserts the isolated launch argv and the
`aws-<profile>` profile-directory flag, the stderr binding announcement, the
sanitization rule, the bare/`--profile default` passthrough, and the two
fallback paths (missing binary, non-Chromium override). Ticket 04 verified the
same behavior on the real macOS machine.
