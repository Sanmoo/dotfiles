# 02 — `safe-pi` wrapper starts Pi in the container

**What to build:** The installed `safe-pi` command. It resolves its own build context through its installed symlink, builds the image only when its tag is missing, and starts Pi in a throwaway container from the current directory — at this point mounting only the working directory, at host path parity. Every Pi argument is forwarded unchanged. Script-owned flags cover rebuilding, refreshing to the latest Pi release, a debug shell, a dry run, and its own usage. It refuses to run as root or without a reachable Docker, and it refuses to nest inside its own sandbox. The Docker process boundary gains a test harness that stubs Docker so the behavior is asserted without a daemon.

**Blocked by:** 01 — Sandbox image that runs Pi

**Status:** resolved

- [x] `safe-pi <pi arguments>` runs Pi in the container with arguments unchanged, in the invoking directory, and exits with Pi's status.
- [x] The image is built on first use and skipped when the current tag already exists.
- [x] Forced rebuild rebuilds the current tag; the refresh flag resolves the latest Pi release, builds that version's tag when absent, and re-points the current tag; a normal run does no version lookup.
- [x] The build context resolves through the installed symlink; a copied script fails with an actionable message, and an explicit override path is honored.
- [x] Running as root, or without a reachable Docker, exits 2 with one actionable message.
- [x] Running inside a sandbox executes Pi directly instead of nesting containers.
- [x] The dry run prints the Docker invocation and exits successfully without touching Docker.
- [x] `-h`, `--help`, and `--version` reach Pi; the `help` subcommand prints the script's own usage.
- [x] A test stubs the Docker boundary and asserts build-skip-rebuild-refresh ordering, exit codes, and argument pass-through, and passes without a Docker daemon.

## Comments

Implemented in `pi/.local/bin/safe-pi` (stow-installed as `~/.local/bin/safe-pi`)
with `tests/safe-pi-wrapper-test.sh`. Integrated into `main` as `b84aa13`.

- Build context resolves with `readlink -f` through the stow symlink to
  `<repo>/safe-pi`. `SAFE_PI_BUILD_CONTEXT` overrides it and accepts either the
  context directory or a Dockerfile path; a copied script exits 2 naming the
  override.
- Tags: `safe-pi:current-u<uid>` (what runs) and `safe-pi:pi-<version>-u<uid>`
  (one per baked Pi version). `--update` resolves the latest release with
  `npm view`, builds that version's tag only when absent, and re-points current.
  `--rebuild` re-builds current with the version read from its label. A normal
  run only inspects the current tag and makes no npm lookup.
- Script flags: `--rebuild`, `--update`, `--shell`, `--dry-run`, `help`.
  `-h`/`--help`/`--version` are forwarded to Pi. Root and unreachable-Docker
  preflight exit 2; the sandbox marker re-enters as Pi instead of nesting.
- Version drift between the image's `safe-pi.pi.version` label and host
  `pi --version` prints a warning naming both. This is a local label/host read,
  not a network lookup.
- `tests/safe-pi-wrapper-test.sh` stubs `docker` and `npm` on PATH and asserts
  build/skip/rebuild/refresh ordering, mount and working-directory parity, the
  sandbox env marker, exit-code pass-through, root/Docker refusals, re-entry,
  the dry run, help versus forwarded flags, symlink/copied-script/override
  resolution, the drift warning, and `--` pass-through. It passes with no Docker
  daemon.
- Verified against the real daemon: the first run built and tagged the image
  (`safe-pi:current-u1000` and `safe-pi:pi-1.1.0-u1000`), a second run skipped
  the build, `--rebuild` re-built the current tag, and `--version` printed
  `1.1.0`. `shellcheck` is clean. The full `tests/*.sh` sweep is 16/18; the two
  failures (`auth-code-token-test.sh`, `herdr-notification-target-test.sh`)
  reproduce on the pre-change `main`.
- Deferred by design: mounts beyond the working directory and the environment
  contract (03), the declared environment and `--prepare` (04), Herdr
  verification (05), and the README usage guide (06).
