# 03 — Container contract: mounts and environment

**What to build:** The complete set of mounts and environment the sandbox runs with, so the container sees the working repository read-write at its host path, the Pi agent directory read-write with extensions and installed Pi packages held read-only, sessions under a container-only path with the matching session-directory variable, the shared skills directory, the configuration checkout, the pi-lens directory, the declared mise configuration, the Herdr configuration directory (socket), the git configuration file, and the SSH agent socket — and nothing else, in particular no Docker socket. Herdr's variables are forwarded only when present, and the wrapper advertises itself to Herdr as Pi. The debug shell and the dry run are how this is inspected.

**Blocked by:** 02 — `safe-pi` wrapper starts Pi in the container

**Status:** ready-for-agent

- [ ] A debug shell shows the invoking uid/gid, the working directory, and every contract path present with its intended mode; read-only entries reject writes.
- [ ] The Pi agent directory is writable (Pi must lock its credential store there), while extensions and installed Pi packages are not writable.
- [ ] Pi inside the sandbox loads the host configuration: settings, prompts, agents, keybindings, the approval extension, the Herdr integration extension, skills from the shared skills directory, and pi-lens configuration.
- [ ] Pi reports its session file under the container-only sessions path, and the corresponding file appears in the host sessions directory.
- [ ] Herdr's variables are forwarded only when set on the host; the wrapper's advertised agent identity is visible to Herdr for the pane.
- [ ] The Docker socket is absent, and the temporary directory is writable but discarded with the container.
- [ ] The stubbed harness asserts every mount's mode and every forwarded variable, including the variables being absent when the host does not set them.

## Comments
