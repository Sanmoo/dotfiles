# safe-pi: run Pi inside a plain Docker container

Status: ready-for-agent

## Problem Statement

Running Pi directly on the host gives every command the agent executes the run of my home directory: it can read or modify the working repository, but also every other repository, my dotfiles checkout, my Pi agent directory, and my credentials. I want Pi's blast radius limited to the repository I am working in, without giving up the parts of the host setup that make Pi usable today: my Pi configuration and credentials, my declared development environment, and the Herdr integration (agent state, blocked notifications, session tracking) that I depend on to run several agents at once.

## Solution

A `safe-pi` command that builds a small image on first use and then runs Pi in a throwaway Docker container. The container sees the working repository (read-write), the Pi agent directory, the Pi configuration checkout, the Herdr socket directory, git and SSH material, and a named volume holding the mise-managed toolchain. It does not see the Docker socket, the host's toolchain tree, or the rest of the home directory.

The development environment is declared once, in the repository's tracked mise configuration, and converged inside the container on every start, so `latest` pins follow the same behavior they have on the host. Herdr keeps working because the container reaches the real Herdr socket for state reports; Herdr's session restore fails closed for sandboxed panes instead of silently starting an unsandboxed Pi.

## User Stories

1. As the machine owner, I want `safe-pi` to build its image on first use, so that a fresh machine needs no manual image build step.
2. As the machine owner, I want a cached image to be reused on later runs, so that starting Pi costs nothing beyond the container start.
3. As the machine owner, I want the toolchain to live in a named volume rather than in the image, so that updating Pi does not force me to download several gigabytes again.
4. As the machine owner, I want the toolchain installed from the repository's declared mise configuration, so that the sandbox environment is declared in one place.
5. As the machine owner, I want the declaration read live from the repository at every start, so that adding or changing a tool takes effect without rebuilding the image.
6. As a developer whose declaration uses `latest` pins, I want the toolchain converged on every start, so that the container tracks new tool releases the way my host does.
7. As a developer working in a repository with its own `.mise.toml`, I want its pins honored inside the container, so that I can build a project with the exact tool version it declares.
8. As a developer, I want per-repository pins to be installed once and reused, so that switching between repositories does not re-download a toolchain.
9. As a developer, I want a repository whose pins differ from the global declaration to still work, so that I am not forced to keep the declaration and every project in sync.
10. As the machine owner, I want a failed toolchain convergence to warn and still open Pi, so that a network problem never blocks me from working.
11. As the machine owner, I want an explicit way to converge the toolchain without opening Pi, so that I can prepare a machine or verify the environment.
12. As the machine owner, I want the mise-managed declaration to be copied from the repository rather than from the host, so that no host toolchain directory leaks into the container.
13. As a Herdr user, I want a sandboxed Pi to report `working`, `blocked`, and `idle`, so that the sidebar and its rollups behave exactly as they do for a host Pi.
14. As a Herdr user, I want the `permission-gate` approval prompt inside the sandbox to surface as `blocked`, so that I notice a pending decision without reading the pane.
15. As a Herdr user, I want the pane to be recognised as a Pi agent even though the foreground process is `docker`, so that labels, waits, and notifications keep working.
16. As a Herdr user, I want a Herdr server restart to keep the socket reachable from a running sandbox, so that a server restart does not silently break state reporting.
17. As a Herdr user, I want Herdr to record the sandboxed session reference, so that session metadata is visible for the pane.
18. As a Herdr user, I want a restored sandboxed pane to come back as a shell rather than as an unsandboxed Pi, so that I am never surprised by isolation that is no longer there.
19. As a Herdr user, I want to re-enter the previous conversation after such a restore with a single command, so that failing closed costs me one keystroke.
20. As a Pi user, I want every `pi` argument to pass through unchanged (`--continue`, `--session`, `--model`, `-p`, `--no-lens`), so that `safe-pi` is a drop-in replacement for `pi`.
21. As a Pi user, I want my credentials to work inside the sandbox, including the rotating OAuth credential for the Codex provider, so that I do not have to log in again per run.
22. As a Pi user, I want my sessions stored where the host Pi stores them, so that a conversation started in the sandbox is resumable from the host and vice versa.
23. As a Pi user, I want my settings, prompts, agents, keybindings, extensions, and npm-installed Pi packages to behave inside the sandbox exactly as they do on the host, so that the sandbox does not feel like a different setup.
24. As a Pi user, I want skills that live outside the Pi agent directory (the shared agent skills directory) to be available, so that the same skill set applies in both environments.
25. As a Pi user, I want pi-lens to keep its configuration and caches, so that its diagnostics and analyzers work inside the sandbox.
26. As a Pi user, I want the agent to be unable to modify my extensions and Pi packages from inside the sandbox, so that a bad turn cannot persist code changes into my host setup.
27. As a developer, I want writes to land in the working repository only, so that a runaway command cannot touch other repositories.
28. As a developer, I want files created inside the sandbox to be owned by me on the host, so that repository permissions and git operations stay clean.
29. As a developer, I want my git identity and SSH agent available, so that committing and pushing from inside the sandbox work.
30. As the machine owner, I want no Docker socket inside the container, so that the sandbox cannot control containers on the host.
31. As the machine owner, I want the container to be removed on exit, so that repeated runs leave no litter.
32. As the machine owner, I want `safe-pi` to refuse to run as root, so that uid parity (and therefore file ownership) is never silently lost.
33. As the machine owner, I want a clear preflight failure when Docker, the Dockerfile, or the resolved symlink target is missing, so that I get one actionable message instead of a partial run.
34. As a developer, I want a debug shell inside the same container the sandbox uses, so that I can inspect the environment when something does not work.
35. As a developer, I want a dry run that prints the exact Docker invocation without touching Docker, so that I can review or adapt what will run.
36. As a developer, I want `safe-pi` to work outside Herdr as well, so that the sandbox is not tied to the multiplexer.
37. As a developer, I want an explicit way to refresh the image's Pi to the latest release, so that following Pi releases costs one short rebuild rather than a Dockerfile edit.
38. As a developer, I want to be warned when the Pi inside the image and the Pi on my host differ, so that version drift is visible instead of confusing.
39. As the machine owner, I want to run `safe-pi` from any directory, so that the sandbox follows the repository I am currently in.
40. As a maintainer, I want the shared behavior (mounts, environment, tagging) covered by a test that stubs the `docker` boundary, so that regressions are caught without a Docker daemon.
41. As the sandbox user, I want a succinct usage guide in the repository README, so that I can work day to day without re-reading the spec.
42. As the sandbox user, I want the guide to lead with the recipes I actually repeat (continue, one-shot, debug shell, prepare, update), so that the common flows are one lookup away.
43. As the sandbox user, I want the guide to name the surprising behaviors and their symptoms, so that I recognise fail-closed restore, read-only extensions, and fail-open convergence instead of debugging them.

## Implementation Decisions

### Artifacts

- Two repository artifacts: a build context (Dockerfile) and the `safe-pi` script.
- The script is installed by stow as part of the `pi` package; the Dockerfile is a repository file that is deliberately **not** installed into `$HOME`.
- Because the installed script is a stow symlink, it resolves its own real path before locating the build context. `readlink -f`/`realpath` follows the symlink chain into the repository; `dirname "${BASH_SOURCE[0]}"` alone would resolve to the installed directory and must not be used for this purpose. An environment override for the build-context path is supported, and a missing build context is a preflight error with an actionable message.
- The script is also the source of the checkout path used for a read-only mount of the configuration repository (see Mounts).

### Image

- Base: `node:26-bookworm-slim`, matching the Node major that runs the host Pi today.
- System packages: certificate bundle, curl, git, ripgrep, fd-find, jq, openssh client, build tooling. The image's own `ripgrep`/`fd`/`jq` satisfy Pi's tool probes and the container's needs independent of the volume.
- mise is installed at build time at a pinned version.
- Pi is installed at build time as a global npm package, parameterized by a Pi version build argument (defaulting to the latest release).
- The image is built for the host uid/gid and the host user name, so the container user matches the invoking user with no runtime remapping.
- The image records labels for the Pi version and the build inputs it was built from.
- Image tagging is deterministic per user: a tag carrying the baked Pi version and the uid, plus a `current` alias for the same user. The `current` tag is what `safe-pi` runs.
- Build behavior: build only when the `current` tag is absent; an explicit refresh resolves the latest Pi release, builds the matching tag if it does not exist yet, and re-points `current`; a forced rebuild re-builds the current tag. No network lookup happens on a normal run.
- When the baked Pi version differs from the host `pi --version`, `safe-pi` prints a warning naming both versions.

### Runtime contract

- `safe-pi [pi arguments...]` runs Pi in the container with the arguments forwarded unchanged, in the current working directory.
- Script-owned flags, consumed by `safe-pi` and never forwarded: forced rebuild, refresh-to-latest, toolchain preparation, debug shell, dry run, and the usage subcommand. `-h`/`--help` and `--version` are forwarded to Pi, because that is what a user typing them expects; `safe-pi help` prints `safe-pi`'s own usage.
- The debug shell starts the same container with the same mounts and environment but with a shell instead of Pi.
- The dry run prints the resolved Docker command and exits successfully without requiring a reachable Docker daemon.
- Exit codes: `2` for usage and preflight failures, `1` for runtime failures, otherwise Pi's own exit status.
- Re-entry guard: the container exports a marker variable; if the marker is already set, the script executes the container's Pi directly instead of nesting containers.

### Container configuration

- Working directory and the working repository are mounted at their host path, and the container's working directory is the same path, so absolute paths in prompts, tool output, and repository metadata stay valid.
- Mounts, decided as a set:

| Host | Container | Mode |
| --- | --- | --- |
| working repository | same path | read-write |
| Pi agent directory | same path | read-write, with the extensions and npm package directories mounted read-only over it |
| Pi agent sessions directory | container-only path | read-write |
| shared agent skills directory | same path | read-only |
| configuration repository checkout | same path | read-only, unless it is the working repository |
| pi-lens directory | same path | read-write |
| declared mise configuration directory (from the checkout) | default mise configuration path | read-only |
| Herdr configuration directory | same path | read-only |
| git configuration file | same path | read-only |
| SSH agent socket | container path | read-write |
| named toolchain volume | container mise data directory | read-write |
| — | temporary directory | tmpfs |
| Docker socket | — | not mounted |

- The Pi agent directory must stay writable: Pi locks its credential store by creating a lock file next to the credential file, and a read-only agent directory makes credential loading fail outright. Read-only sub-mounts over the extensions and npm package directories keep installed code immutable while leaving agent state writable.
- The configuration checkout is mounted because Pi's settings file, keybindings, prompts, extension files, and the pi-lens configuration are symlinks into it. Without it, Pi loses settings, prompts, the approval extension that feeds Herdr's blocked state, and pi-lens configuration.
- The shared agent skills directory is mounted because the agent directory's skill entries are symlinks into it.
- Herdr's configuration *directory* is mounted rather than the socket file, so a Herdr server restart (which recreates the socket) does not leave a stale socket inside running containers.
- Environment contract: host identity variables needed by tools and Pi (`HOME`, `USER`, locale, terminal, timezone), the mise data directory pointing at the volume, the session directory environment variable pointing at the container-only sessions path, the SSH agent socket path, and the Herdr variables (`HERDR_ENV`, `HERDR_SOCKET_PATH`, `HERDR_PANE_ID`) forwarded only when they are set on the host. The wrapper advertises itself to Herdr as a Pi process so the pane is attributed to Pi even though the foreground process is Docker.
- Pi's agent directory needs no explicit override: with `HOME` preserved and the directory mounted at its host path, Pi's defaults resolve correctly.
- Toolchain convergence: the entrypoint runs mise's install step non-interactively before starting Pi, which is idempotent and fast when satisfied, and prints progress on the first (long) run. The declared tool shims are placed before the image's own binaries on `PATH`, so the declaration wins for project tools. The image's Node remains the fallback when the declaration does not pin Node; the entrypoint verifies that the Node Pi will run on satisfies Pi's engine requirement and fails with a clear message otherwise, rather than starting a broken Pi.
- Fail-open: a failed convergence prints a warning naming the failed step and Pi still starts. Toolchain preparation is the strict mode and reports the failure as its exit status.
- Concurrency: the toolchain volume may be converged by more than one container at a time; the entrypoint serializes the install step so concurrent starts do not race.

### Herdr integration

- State reporting comes from the integration extension that Herdr installs into the host Pi agent directory, which is part of the mounted agent directory. The blocked state comes from the approval extension in the configuration checkout emitting the Herdr event that the integration consumes. Both are therefore unchanged by the sandbox as long as the socket is reachable and the checkout is mounted.
- Session restore: the session path reported to Herdr is the container-only sessions path. Herdr's native agent session restore derives its resume command from a host path, so a sandboxed pane's reference is deliberately invalid on the host and the pane restores as a shell in the saved directory instead of as an unsandboxed Pi. `safe-pi --continue` (or the equivalent) re-enters the sandbox with the same conversation, since sessions are stored in the shared host directory.
- Two consequences are accepted and documented in the ADR: inside the container the same sessions directory is visible twice (under the agent directory and at the container-only path; Pi uses the latter), and sandboxed panes do not receive Herdr's automatic session resume.
- A follow-up spike (separate ticket) will test whether a container-side Herdr integration can report `safe-pi --session <path>` as its own resume command, which would restore automatic resume while keeping the sandbox.

### Configuration repository changes

- The domain glossary gains the new vocabulary introduced here.
- An architecture decision record captures the isolation boundary, the declared-environment decision, and the restore trade-off, including the alternatives that were rejected.
- The repository README gains the usage guide (see Documentation below), including the accepted limitations (no Docker socket, no credential boundary, no automatic Herdr session resume).

### Documentation

- The deliverable includes a succinct usage guide written for day-to-day use, not a reference manual: a first-run description, the recipes that cover everyday flows, the script-owned flag table, a plain-language summary of what the sandbox does and does not see, the behaviors that surprise people, where the artifacts live, and a symptom-to-cause troubleshooting table.
- The guide is a section of the repository's existing `How to` README, following its prose style, and is cross-referenced from the Herdr section, so there is exactly one place to read.
- While the command does not exist yet, the guide's draft lives beside this spec as a planning artifact. Implementation moves it into the README and deletes the draft.
- Writing the guide is part of the work, not a follow-up: it is the acceptance surface for the command's interface, and a recipe that reads badly in the guide is a signal to change the flag.

## Testing Decisions

- One test seam: the external `docker` process boundary. The test puts a stub `docker` (and a stub package-manager query for the refresh path) on `PATH` and runs the real script, asserting on the arguments, environment, and ordering it produces. This is the highest available seam, it is the only external dependency the script has, and it needs no Docker daemon.
- A good test here asserts *observable behavior of the script toward its one collaborator* — which mounts, in which mode, which environment variables, which tag, which ordering (build before run, prepare without run), and which exit code — never internal shell structure, helper function names, or the exact text of help output beyond the usage exit code.
- Cases to cover: build when the image is absent; skip the build when the tag exists; forced rebuild; refresh path resolving and building a new tag; preparation mode running convergence and not Pi; preparation mode surfacing convergence failure as a non-zero exit; dry run printing a command and invoking nothing; argument pass-through including flags that look like script flags after `--`; refusal when running as root; refusal when Docker is missing; re-entry guard executing Pi; read-only versus read-write mount modes for each contract entry; the container-only sessions path variable; Herdr variables forwarded only when present in the environment; the toolchain volume name; and the working directory being the invoking directory.
- Prior art: the existing script tests in `tests/` stub external commands and fixtures on `PATH` and assert on emitted JSON, arguments, and exit codes. This test follows the same shape.
- Manual verification, recorded in the ADR rather than automated: a real Herdr run checking agent state, blocked prompt, and pane attribution; a Herdr server restart confirming the pane returns as a shell and `safe-pi --continue` resumes the conversation; the debug shell confirming uid, mounts, `mise ls`, and `pi --version`; an offline start confirming the fail-open warning; and a first-run measurement of the toolchain convergence.

## Out of Scope

- Docker Sandboxes, OpenShell, Gondolin, or any managed sandbox replacing plain Docker.
- Credential proxying or keeping provider credentials out of the container.
- Network egress restrictions inside the container.
- The Herdr custom-integration resume spike (own ticket).
- macOS support (`pi-mac`), Windows, or multi-user machines.
- Installing or updating Pi packages, extensions, or the Pi binary from inside the container.
- Per-project toolchain volumes.
- Publishing, signing, or distributing the image beyond the local Docker daemon.
- Interactive Pi features that depend on the host's desktop session.

## Further Notes

- Evidence behind the decisions, gathered while designing: a read-only Pi agent directory fails credential loading (`EACCES` creating the credential lock file) while a writable agent directory with read-only extensions and npm package directories runs normally; a fresh Docker named volume is seeded from image content and a later image does not re-seed it (which is why the toolchain volume is *not* keyed to a baked baseline in the chosen design); mounting host toolchain binaries into a Debian-based image fails for several core tools and works only in a distro-matched image, which is why the environment is installed inside the container instead of mounted from the host; and the mounted Pi packages' native artifacts are stable-ABI prebuilds that load under both the host and image Node majors.
- The sandbox is a filesystem boundary, not a credential boundary: the agent can read every credential and every session in the mounted agent directory. This is the accepted cost of using the host Pi configuration unchanged.
- The agent can modify the mounted agent directory's state (settings, credential file, caches). This is accepted; only extensions and npm-installed packages are held read-only.
- Follow-ups worth their own tickets: the Herdr resume spike; an explicit way to reset the toolchain volume; and an optional mode that pulls a published image on machines where building is undesirable.
