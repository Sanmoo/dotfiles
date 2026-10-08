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

**Declared environment**:
The set of tool versions the sandbox installs, read from the repository's tracked mise configuration instead of from the host's installed toolchain.
_Avoid_: dev environment, toolchain (when meaning the declaration)

**Toolchain volume**:
The named Docker volume that keeps the declared environment's installed tools across sandbox runs, distinct from the image itself.
_Avoid_: cache volume, mise volume

**Host path parity**:
Mounting a host directory into the sandbox at the same absolute path, so absolute paths and symlinks keep resolving.
_Avoid_: mount mapping, path mapping

**Fail-closed restore**:
Herdr behavior where a sandboxed pane's session reference cannot be resumed on the host, so a restored pane returns as a shell instead of as an unsandboxed agent.
_Avoid_: disabled restore, broken restore

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
