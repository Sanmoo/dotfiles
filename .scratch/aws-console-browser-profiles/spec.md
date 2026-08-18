# aws-console: browser-profile isolation & service deep-links

Status: ready-for-agent

## Problem Statement

`aws-console` signs into the AWS console through a federated URL, but the URL is opened in the default browser's main profile. Logging into a second AWS account therefore replaces the first account's console session — the developer cannot stay logged into two accounts at the same time. Additionally, the script only ever lands on the generic console home; reaching a specific service (e.g. ECS) requires manual navigation every time.

## Solution

Each named AWS profile gets its own browser profile, derived deterministically from the AWS profile name, so every account keeps its own console session. A new optional positional service argument lands the federated session directly on that service's console page, in the region configured for the AWS profile. The tool stays cross-platform: Chrome on Linux, Edge on macOS, both driven by the same direct-exec launch path.

## User Stories

1. As a developer working with multiple AWS accounts, I want each named AWS profile to open the console in its own browser profile, so that I can stay logged into several accounts simultaneously.
2. As a developer, I want the browser profile to be derived deterministically from the AWS profile name (e.g. `rev-qual` → `aws-rev-qual`), so that I never have to configure or remember a mapping.
3. As a developer, I want the browser profile to be created automatically on first use, so that a new account works with zero setup.
4. As a developer, I want the browser profile name sanitized when the AWS profile contains characters that are awkward in a directory name, so that exotic profile names still work.
5. As a developer, I want `aws-console ecs --profile rev-qual` to open the ECS console inside the `rev-qual` browser profile, so that I land exactly where I need to work, in one command.
6. As a developer, I want a curated set of common services to deep-link to, so that the consoles I use most are one command away.
7. As a developer, I want the deep-link URL to carry the region configured in the AWS profile for regional services, so that the console opens in the region I use.
8. As a developer, I want global services to omit the region parameter, so that the URL never carries a meaningless region.
9. As a developer, I want an error listing the supported services when I pass an unknown one, so that I discover valid names instead of guessing.
10. As a developer, I want bare `aws-console` (no `--profile`) to behave exactly as it does today, so that my default account session keeps living in my main browser profile.
11. As a developer, I want `--profile default` to behave like no profile, so that naming the default explicitly does not spawn an extra browser profile.
12. As a developer on Linux, I want isolation to use google-chrome-stable, so that it matches my daily browser.
13. As a developer on macOS, I want isolation to use Microsoft Edge, so that it matches my daily browser.
14. As a developer, I want to override the browser via an environment variable, so that I can switch browsers without editing the script.
15. As a developer, I want a warning and a graceful fallback to the default browser when the resolved browser is missing or unlikely to support profile isolation, so that the command still opens the console instead of failing.
16. As a developer, I want the isolated launch to announce on stderr which browser profile will be used, so that I can confirm the binding at a glance.
17. As a developer, I want `--stdout` to keep printing only the URL on stdout, so that piping stays clean.
18. As a developer, I want the signin URL's Destination to point at the service page when a service is given, so that the federation redirect lands where I asked.
19. As a developer, I want the federation endpoint overridable via an environment variable that defaults to today's URL, so that tests can run offline and alternative endpoints remain possible.
20. As a developer, I want the script to keep working as a plain executable with the shebang unchanged, so that my current macOS workflow is untouched.
21. As a developer, I want an offline test harness that stubs AWS, federation, and the browser at the process boundary, so that the script is regression-tested without network access or real credentials.

## Implementation Decisions

- The script remains a single Python executable; the shebang is unchanged.
- **Binding rule**: the browser profile directory is `aws-<sanitized AWS profile>`, where sanitization replaces every character outside `[A-Za-z0-9._-]` with `-`. Two AWS profiles that sanitize to the same name share a browser profile — an accepted, documented limitation with no collision logic.
- **Isolation trigger**: isolation applies only when `--profile` is given and is not `default`. Without `--profile` (or with `--profile default`), the script keeps today's behavior of opening the signin URL via the platform's default browser.
- **Browser resolution**: per-OS defaults — Linux resolves `google-chrome-stable`; macOS resolves the Microsoft Edge app-bundle binary. An environment variable override (name or full path) takes precedence. The resolver is a pure function of the platform name so it can be tested from any host OS.
- **Launch**: the resolved binary is executed directly and detached, with `--profile-directory=<binding>` followed by the signin URL. The same code path serves both OSes.
- **Degradation**: if the resolved browser binary cannot be found or its name does not suggest a Chromium-family browser, a warning goes to stderr and the script falls back to opening via the platform's default browser (no isolation). The command does not fail.
- **Service deep-link**: a new optional positional argument accepts a curated service name (`ecs`, `ec2`, `lambda`, `s3`, `cloudwatch`, `logs`, `rds`, `dynamodb`, `ecr`, `iam`, `vpc`, `route53`, `sns`, `sqs`, `eks`) and maps it to that service's current console path (e.g. ECS uses the current `/ecs/v2/home` console). An unknown name exits non-zero with the list of supported names.
- **Region**: the deep-link URL appends `?region=<configured region>` for regional services when the AWS profile configures a region; global services (e.g. `iam`, `s3`) never receive a region parameter.
- **Destination**: when a service is given, the federation Destination is the service's console URL; otherwise it is today's account landing URL. The federation endpoint base URL is overridable via an environment variable defaulting to the URL hardcoded today.
- **Reporting**: isolated launches print the browser profile binding to stderr; `--stdout` mode also reports the binding on stderr while stdout carries only the signin URL.
- **CLI contract**: `aws-console [service] [--profile NAME] [--stdout]`. Existing flags keep their meaning; the positional is optional.
- The glossary terms **AWS profile**, **browser profile**, **binding**, and **service deep-link** are recorded in the project glossary. No ADR is written for this feature.

## Testing Decisions

- A good test asserts only external behavior: the argv handed to the stubbed browser, text on stdout/stderr, and exit codes. Never implementation details of the script's internals.
- **Single seam: the CLI process boundary.** The harness runs the real script as a subprocess with dependencies stubbed by environment, following the repo's existing prior art (the sibling bash test harness for the ECS logs script).
- Dependency stubs in the harness: credentials and region via standard AWS environment variables; STS via the botocore per-service endpoint variable pointed at a local HTTP stub serving the canonical GetCallerIdentity XML; federation via the new endpoint override env var pointed at a local HTTP stub serving a SigninToken JSON payload; the browser via fake browser scripts (the isolation override env var for isolated launches, the standard browser env var for non-isolated ones) that record their argv.
- The harness additionally imports the script's pure helpers (binding sanitization, service URL building, browser resolution) and asserts on them directly, because platform-dependent branches cannot be exercised from a single host OS.
- Covered cases: isolated launch passes the correct `--profile-directory` and signin URL; non-isolated launch falls back to the default browser; `--stdout` keeps stdout URL-only while reporting the binding on stderr; unknown service exits non-zero listing supported names; regional services carry the configured region and global ones do not; binding sanitization; per-OS browser resolution including the environment override.

## Out of Scope

- Windows support.
- Isolation for non-Chromium browsers (Safari, Firefox).
- A configurable binding mapping file; the deterministic rule is the only binding mechanism.
- Deep links beyond each service's home page (no sub-page paths).
- Chrome/Edge account sync, extensions, or preferences inside the auto-created browser profiles.
- Changes to credential handling: SSO flows, credential refresh, and federation token mechanics stay exactly as they are today.
- An ADR for the binding model.

## Further Notes

- Auto-created browser profiles start fresh (no Chrome sync, extensions, or saved passwords), but the federated signin URL authenticates without any credential entry, so console access works immediately on first use.
- The default account's existing session in the main browser profile is untouched; only named AWS profiles are isolated.
- The federation endpoint override exists primarily as a test seam, but it doubles as future-proofing for pointing the tool at an alternative federation endpoint.
