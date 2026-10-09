# Dotfiles

Personal configuration and command-line tooling managed with GNU Stow, including an HTTP client (`http`) used for ad-hoc API consumption against OpenCollection collections.

## Language

**Collection**:
A directory containing a manifest plus one or more request documents; identified by its manifest.
_Avoid_: collection folder, project, collection dir

**Manifest**:
The collection's top-level YAML file (`opencollection.yaml`, `opencollection.yml`, `collection.yaml`, or `collection.yml`) holding `info`, `variables`, `config.environments`, client certificates (`config.clientCertificates`), and request defaults.
_Avoid_: collection config, opencollection file

**Request document**:
A YAML file (not a manifest) describing one named HTTP request — recognized by `type: http` or a `request:` block with `method`/`url`.
_Avoid_: request file, endpoint doc

**Request**:
The runnable HTTP call resolved from a request document (method, URL, headers, params, body).
_Avoid_: call, endpoint (when meaning the resolved call rather than the document)

**Environment**:
A named config under `config.environments`, selectable with `-e`, holding variables and optionally client certificates. Distinct from the calling shell's environment.
_Avoid_: env, variable set

**Client certificate**:
An entry in `config.clientCertificates` (collection) or `config.environments[].clientCertificates` (environment) — `domain`, `type: pem`, `certificateFilePath`, `privateKeyFilePath`, optional `passphrase`/`disabled` — applied to requests whose URL host matches the `domain` (wildcard `*` allowed).
_Avoid_: mtls config, tls block

**Comando equivalente**:
The `http oc ...` command printed in interactive mode that reproduces a run (the code names it `equivalent command`).
_Avoid_: equivalent command (in user-facing prose)

**Body override**:
`-d`/`-f` supplying the request body from the command line, replacing the manifest's `request.body`.
_Avoid_: inline body, CLI body (when meaning the override mechanism)

**Post-response script**:
A request document's program that processes the response to its request.
_Avoid_: shell script (when meaning response processing), post-request hook

**Runtime variable**:
A temporary value available during one request execution, shared by its post-response scripts and distinct from persisted collection or Environment variables.
_Avoid_: environment variable (when meaning a temporary script value)

**Shell export**:
An explicit mapping from a script-produced runtime variable to an exported variable in the calling shell session, available to subsequent commands in that session.
_Avoid_: Environment update, collection variable (when meaning a shell export)

## safe-pi

**Sandbox**:
The throwaway container Pi runs in when started through `safe-pi`.
_Avoid_: container (when meaning the isolation boundary), devcontainer

**Permission gate**:
The `permission-gate` extension: an advisory confirmation prompt before a dangerous bash command on the host, not an isolation boundary. Inside the sandbox it registers nothing, so a dangerous command runs without a prompt even though the repository, the sessions directory, the toolchain volume and the forwarded SSH agent are all reachable from there.
_Avoid_: sandbox guard, sandbox protection, isolation (when meaning the gate)

**Declared environment**:
The set of tool versions the sandbox installs, read from the repository's tracked mise configuration instead of from the host's installed toolchain.
_Avoid_: dev environment, toolchain (when meaning the declaration)

**Toolchain volume**:
The named Docker volume that keeps the declared environment's installed tools, and mise's cache and state, across sandbox runs, distinct from the image itself.
_Avoid_: cache volume, mise volume

**Converge**:
The sandbox making its installed tools match the declared environment: probe, then install only what the probe reports missing, into the toolchain volume. Convergence runs on every sandbox start, before the command, and is silent when it has nothing to do.
_Avoid_: sync, provisioning, install step

**Steady start**:
A sandbox start whose declared environment is already converged, so convergence installs nothing, prints nothing, and adds no noticeable delay. The counterpart of a first run.
_Avoid_: warm start, second run, later run

**Precompiled OTP target**:
The operating-system release whose precompiled Erlang/OTP build the sandbox installs instead of compiling OTP from source. It is chosen to be compatible with the image's system libraries, and it is a sandbox-only choice: the host keeps installing OTP its own way.
_Avoid_: binary build, prebuilt Erlang, ubuntu build

**Sandbox locale**:
The locale a sandbox start runs under: the host's forwarded `LANG`/`LC_ALL`/`LC_CTYPE` when the image can run UTF-8 under them, and glibc's built-in `C.UTF-8` otherwise. The image generates `en_US.UTF-8`, the locale the host forwards today; a locale the image does not ship, or a name carrying no UTF-8 codeset at all (`C`, `POSIX`), becomes `C.UTF-8` rather than the POSIX fallback glibc would otherwise take.
_Avoid_: container locale, image locale

**Host path parity**:
Mounting a host directory into the sandbox at the same absolute path, so absolute paths and symlinks keep resolving.
_Avoid_: mount mapping, path mapping

**Self-reported resume command**:
The `resume_argv` a sandboxed pane's reporter attaches to its Herdr reports (`safe-pi --session <id>`, naming the session that was running, with `safe-pi -c` as the fallback): Herdr persists it with the pane and, after a server restart, types it into the restored pane's shell in the saved working directory, so the pane comes back inside a fresh sandbox in the same conversation. Herdr consults it before its built-in official resume table, and it is the sandbox's substitute for the native `agent_session` reference, which is stored only for official `herdr:*` sources.
_Avoid_: resume hook, restore command, resume path

**Sandbox reporter**:
The container-side Herdr integration (`herdr-reporter.ts`) that reports a sandboxed pane's `working` and `idle` state, its session reference, and a self-reported resume command, under the `safe-pi` source, and that releases the pane when the sandboxed Pi quits. It replaces the Herdr-managed integration inside the sandbox, because Herdr ignores that integration's `herdr:pi` source for a pane whose foreground process is not a detected Pi (the sandbox's foreground is `docker`). The managed integration is neutralised by withholding the variables that activate it; the reporter gets the socket and pane under sandbox-owned names.
_Avoid_: Herdr integration (when meaning the sandbox-owned reporter), host integration

**Pane release**:
The clearing of a pane's agent attribution — its name, state, and stored resume command — when the agent that held it is no longer running. A reporter sends it when the user actually quits; it is not a session change, which reports the new session instead.
_Avoid_: clear agent, unregister, detach

**Idle-shell safety net**:
Herdr's fallback that clears a self-reported agent once the pane's shell is back at its prompt with nothing running, for a reporter that never sent a pane release. It applies only to agents Herdr cannot identify by its own process detection, so a reporter that claims a process-detectable agent name gets no fallback.
_Avoid_: shell-return cleanup, timeout, keepalive

## aws-console

**AWS profile**:
A named credential set in the AWS config, passed to `aws-console` via `--profile`.
_Avoid_: profile (when meaning the browser-side profile)

**Browser profile**:
An isolated browser storage (Chrome/Edge `--profile-directory`) with its own cookies, sessions, and logins.
_Avoid_: profile (when meaning the AWS-side profile)

**Binding**:
The deterministic mapping from an AWS profile name to a browser profile directory (`aws-<sanitized-profile>`).
_Avoid_: mapping, link (when meaning this relationship)

**Service deep-link**:
The positional service argument (`ecs`, `lambda`, …) that lands the federated console session directly on that service's console page.
_Avoid_: service URL (when meaning the argument), destination

## Quality gateway

**Quality gateway**:
This repository's automated validation of a change, taken as a whole. It runs in two phases with different cost and different obligations; anything that runs only part of it is not the gateway.
_Avoid_: CI (there is none), test suite (when meaning the gateway), pipeline

**Test suite**:
Every test this repository owns, in all the places they live — the shell tests, the `general/bin` tests, and the Pi agent tests. Not a synonym for the `tests/` directory, which holds only some of them.
_Avoid_: tests folder, the tests (when meaning the suite)

**Fast gate**:
The phase of the Quality gateway run while working on a change, kept cheap enough to re-run freely by running only tests that are fast individually and by running them in parallel. A green Fast gate is necessary but never sufficient to finish a task.
_Avoid_: fast suite, quick tests, smoke tests (when meaning this phase)

**Full gate**:
The phase of the Quality gateway that every test belongs to, and that must pass before a task is considered finished. It is the Fast gate's set plus the slow-tier tests, and it ends with an explicit verdict line rather than an inferred one.
_Avoid_: slow suite, full test run (when meaning this phase), nightly

**Slow tier**:
The tests excluded from the Fast gate because they alone cost about as much as the whole Fast gate budget. A slow-tier test is marked as such in its own file and is still a required test, not an optional extra.
_Avoid_: slow test, e2e test (when meaning this tier), flaky test
