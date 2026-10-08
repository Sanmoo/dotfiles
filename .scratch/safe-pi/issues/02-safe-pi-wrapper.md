# 02 — `safe-pi` wrapper starts Pi in the container

**What to build:** The installed `safe-pi` command. It resolves its own build context through its installed symlink, builds the image only when its tag is missing, and starts Pi in a throwaway container from the current directory — at this point mounting only the working directory, at host path parity. Every Pi argument is forwarded unchanged. Script-owned flags cover rebuilding, refreshing to the latest Pi release, a debug shell, a dry run, and its own usage. It refuses to run as root or without a reachable Docker, and it refuses to nest inside its own sandbox. The Docker process boundary gains a test harness that stubs Docker so the behavior is asserted without a daemon.

**Blocked by:** 01 — Sandbox image that runs Pi

**Status:** ready-for-agent

- [ ] `safe-pi <pi arguments>` runs Pi in the container with arguments unchanged, in the invoking directory, and exits with Pi's status.
- [ ] The image is built on first use and skipped when the current tag already exists.
- [ ] Forced rebuild rebuilds the current tag; the refresh flag resolves the latest Pi release, builds that version's tag when absent, and re-points the current tag; a normal run does no version lookup.
- [ ] The build context resolves through the installed symlink; a copied script fails with an actionable message, and an explicit override path is honored.
- [ ] Running as root, or without a reachable Docker, exits 2 with one actionable message.
- [ ] Running inside a sandbox executes Pi directly instead of nesting containers.
- [ ] The dry run prints the Docker invocation and exits successfully without touching Docker.
- [ ] `-h`, `--help`, and `--version` reach Pi; the `help` subcommand prints the script's own usage.
- [ ] A test stubs the Docker boundary and asserts build-skip-rebuild-refresh ordering, exit codes, and argument pass-through, and passes without a Docker daemon.

## Comments
