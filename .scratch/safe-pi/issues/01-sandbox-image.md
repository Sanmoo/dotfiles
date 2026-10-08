# 01 — Sandbox image that runs Pi

**What to build:** A buildable image definition for the sandbox. Built for a given host user, the image provides Pi (installed at a build-argument-selected release), mise as the installer for the declared environment, and the base utilities Pi probes for and the container needs (git, ripgrep, fd, jq, an SSH client, curl, build tooling). The container user matches the host uid/gid by construction, and the image records the Pi version and its build inputs as labels. Built by hand and run non-interactively, it prints Pi's version and nothing else is required.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Building with the host uid, gid, and user name arguments succeeds, and processes in the resulting image run as that uid/gid.
- [ ] Running the image non-interactively prints Pi's version, matching the version selection passed to the build.
- [ ] The baked Pi version and the build inputs are readable back from the image as labels.
- [ ] mise is installed at a pinned version and runs, without installing anything yet.
- [ ] git, ripgrep, fd, jq, an SSH client, curl, and build tooling resolve on PATH without any mounted toolchain.
- [ ] The image needs no credentials, no host paths, and no Docker socket to build or run.

## Comments
