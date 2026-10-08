# 01 — Sandbox image that runs Pi

**What to build:** A buildable image definition for the sandbox. Built for a given host user, the image provides Pi (installed at a build-argument-selected release), mise as the installer for the declared environment, and the base utilities Pi probes for and the container needs (git, ripgrep, fd, jq, an SSH client, curl, build tooling). The container user matches the host uid/gid by construction, and the image records the Pi version and its build inputs as labels. Built by hand and run non-interactively, it prints Pi's version and nothing else is required.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] Building with the host uid, gid, and user name arguments succeeds, and processes in the resulting image run as that uid/gid.
- [x] Running the image non-interactively prints Pi's version, matching the version selection passed to the build.
- [x] The baked Pi version and the build inputs are readable back from the image as labels.
- [x] mise is installed at a pinned version and runs, without installing anything yet.
- [x] git, ripgrep, fd, jq, an SSH client, curl, and build tooling resolve on PATH without any mounted toolchain.
- [x] The image needs no credentials, no host paths, and no Docker socket to build or run.

## Comments

Implemented in `safe-pi/Dockerfile` (build context `safe-pi/` at the repository
root, deliberately outside the `pi` stow package). Integrated into `main` as
`91e6cb5`.

Build arguments: `BASE_IMAGE` (default `node:26-bookworm-slim`), `PI_VERSION`
(default `1.1.0`, the latest release at the time of writing; the wrapper will
pass the release it resolves), `MISE_VERSION` (pinned `2026.10.4`), `UID`,
`GID`, `USERNAME`. Labels: `safe-pi.base.image`, `safe-pi.pi.version`,
`safe-pi.mise.version`, `safe-pi.username`, `safe-pi.uid`, `safe-pi.gid`.

Verified by building and running the image:

- Default build with only `UID=1000 GID=1000 USERNAME=sanmoo`: `docker run --rm <image> id`
  reports `uid=1000(sanmoo) gid=1000(sanmoo)`; a second build with
  `UID=4242 GID=4343 USERNAME=testuser` reports `uid=4242(testuser)`.
- `docker run --rm <image>` prints `1.1.0`, matching `PI_VERSION`; the
  `safe-pi.pi.version` label reads `1.1.0` even when no `PI_VERSION` is passed.
- `docker run --rm <image> mise --version` prints `2026.10.4`.
- `git`, `rg`, `fd`, `jq`, `ssh`, `curl`, `gcc`, `make`, and `python3` all
  resolve on `PATH` with no mounted toolchain.
- `/var/run/docker.sock` is absent, and the Dockerfile copies no host paths and
  needs no credentials.
