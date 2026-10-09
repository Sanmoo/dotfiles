# 04 — Declared environment installed inside the container

**What to build:** The sandbox converges the declared environment on every start: the container installs the toolchain declared in the repository's tracked mise configuration into a named volume, puts the declared tools ahead of the image's own binaries, and then starts Pi. Per-repository pins are honored and reused. Changing the declaration takes effect on the next start without rebuilding the image. Convergence is fail-open at startup (a warning, then Pi still starts) and strict when explicitly requested. The start also verifies that the Node Pi will run on satisfies Pi's engine requirement.

**Blocked by:** 03 — Container contract: mounts and environment

**Status:** resolved

- [x] The first start installs the declared toolchain into the named volume and reports progress; later starts install nothing and add no noticeable delay.
- [x] The declared tools are on PATH in the sandbox, ahead of the image's own binaries.
- [x] A repository's own pin is installed on first use and reused afterwards instead of being downloaded again.
- [x] Editing the declaration takes effect on the next start without rebuilding the image.
- [x] The prepare flag converges and exits without starting Pi, and surfaces a convergence failure as a non-zero exit.
- [x] A start without network access warns and still opens Pi with the tools already in the volume.
- [x] When the resolved Node cannot satisfy Pi's engine requirement, the start fails with a message naming the requirement instead of launching a broken Pi.
- [x] Two containers starting at once share the volume without corrupting it.
- [x] The stubbed harness asserts the volume mount, the path ordering, the prepare exit code, and the fail-open warning.

## Comments

Implemented in `safe-pi/entrypoint.sh`, the image's `ENTRYPOINT` (so the
debug shell and prepare runs converge too), with `--prepare` in
`pi/.local/bin/safe-pi`. Integrated as `942b3c8`, after a rebase onto `main`.

Decisions to confirm:

- **Trust.** The entrypoint sets `MISE_TRUSTED_CONFIG_PATHS` to the working
  directory, so the repository's own `.mise.toml` is honoured. Pi already runs
  whatever the repository contains, so this adds no exposure beyond the sandbox.
- **Cache and state in the volume.** `MISE_CACHE_DIR` and `MISE_STATE_DIR` sit
  under the data directory. State lost with a throwaway container would let an
  interrupted install look complete, and cache lost would refetch `latest`
  pins every start. The spec listed only the data directory, so this is beyond
  it; ADR 0002 and the glossary record it.
- **Probe before install.** A start runs `mise install --dry-run-code` first and
  installs only when that reports something missing. A steady start is silent.
- **Engine check fails open only when unreadable.** An unsatisfied range refuses
  to start Pi, naming the requirement. If Pi's package or npm's bundled semver
  cannot be read, a warning is printed and Pi starts. The image always has both,
  so this path is a safeguard against layout changes; say if it should fail
  closed instead.
- **Stale images are rebuilt.** An image built before the entrypoint existed
  carries no `safe-pi.entrypoint` label, and is rebuilt on next use. Without
  this, `--prepare` would pass to Pi, and normal starts would skip convergence.
- **Test seams.** The entrypoint has its own stubbed harness for `mise`, `pi`,
  and `npm`, alongside the `docker` harness. The entrypoint runs inside the
  container, so it can't be exercised at the `docker` boundary alone.

Verified with stubs (`tests/safe-pi-entrypoint-test.sh`,
`tests/safe-pi-wrapper-test.sh`) and against the real daemon, with the wrapper
and a scratch copy of the checkout declaring `node` and `jq`, then `shfmt` and
`lazygit`:

- First start installs with progress; a steady start is silent in about 0.3s,
  and a `--prepare` run in the repository reuses its pin.
- The declared `jq` shadows the image's `/usr/bin/jq`; `node` resolves to the
  declared version inside the repository and outside it.
- Editing the declaration takes effect on the next start, with no rebuild.
- Offline: a Pi start warns, naming `mise install --yes`, and still runs; a
  `--prepare` run exits 1.
- Node 22.0.0 is refused with `(node >=22.19.0)` named; a debug shell still
  opens.
- Two containers converging together: the second reports it is waiting, then
  finds the tool installed.

Not verified: the full declaration's first-run time (the erlang and elixir
installs may build from source, so this is a long run for the manual
measurement), and Herdr behaviour, which belongs to ticket 05. The
`latest`-from-cache claim is checked offline here but not by a test.

### Correction from ticket 05

The full declaration does not converge in the image. `erlang@latest` fails to
build from source (`configure: error: No curses library functions found`; the
image also lacks `autoconf` and `libssl-dev`), and `elixir@latest` is skipped as
a failed dependency. `safe-pi --prepare` exits non-zero, and because the
entrypoint probes before installing, **every** normal start re-attempts the
failing build (~30 s) before failing open. The "steady start is silent in about
0.3 s" claim holds only for a declaration whose tools all install.
