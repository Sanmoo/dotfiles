# 04 — Declared environment installed inside the container

**What to build:** The sandbox converges the declared environment on every start: the container installs the toolchain declared in the repository's tracked mise configuration into a named volume, puts the declared tools ahead of the image's own binaries, and then starts Pi. Per-repository pins are honored and reused. Changing the declaration takes effect on the next start without rebuilding the image. Convergence is fail-open at startup (a warning, then Pi still starts) and strict when explicitly requested. The start also verifies that the Node Pi will run on satisfies Pi's engine requirement.

**Blocked by:** 03 — Container contract: mounts and environment

**Status:** ready-for-agent

- [ ] The first start installs the declared toolchain into the named volume and reports progress; later starts install nothing and add no noticeable delay.
- [ ] The declared tools are on PATH in the sandbox, ahead of the image's own binaries.
- [ ] A repository's own pin is installed on first use and reused afterwards instead of being downloaded again.
- [ ] Editing the declaration takes effect on the next start without rebuilding the image.
- [ ] The prepare flag converges and exits without starting Pi, and surfaces a convergence failure as a non-zero exit.
- [ ] A start without network access warns and still opens Pi with the tools already in the volume.
- [ ] When the resolved Node cannot satisfy Pi's engine requirement, the start fails with a message naming the requirement instead of launching a broken Pi.
- [ ] Two containers starting at once share the volume without corrupting it.
- [ ] The stubbed harness asserts the volume mount, the path ordering, the prepare exit code, and the fail-open warning.

## Comments
