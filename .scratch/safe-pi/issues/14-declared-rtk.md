# 14 — Declare rtk so Pi's command rewrites work in the sandbox

**What to build:** Declare `rtk` in the repository's tracked mise configuration,
so the sandbox's convergence installs it into the toolchain volume and the
`pi-rtk-optimizer` extension finds it. The extension probes the rtk binary on
every Pi `session_start` (`which rtk`, then `rtk --version`) and, with
`guardWhenRtkMissing` on, warns and bypasses its command rewriting when the probe
fails. On the host rtk is installed at `~/.local/bin/rtk` by rtk-ai's
`install.sh`; the sandbox has neither that path nor a declared rtk, so a
sandbox start opens with
`pi-rtk-optimizer: rtk binary unavailable, command rewrite bypassed`.

The fix is one entry in the declaration — `rtk = "latest"` — plus a comment
naming `pi-rtk-optimizer` as the consumer. No image, wrapper, mount, or
extension-config change: this is the declared environment doing what it exists
for, and it stays consistent with ADR 0002's rejection of mounting the host
toolchain.

Reliability was verified before this ticket was written, on the real image
(`docker run --entrypoint bash safe-pi:current-u1000`): mise `2026.10.4` resolved
`rtk@latest` to 0.51.0 through its own registry entry
(`aqua:rtk-ai/rtk`, `explicit_backend = false`), downloaded
`rtk-x86_64-unknown-linux-musl.tar.gz` in 4 s, and `mise exec rtk@latest -- rtk
--version` printed `rtk 0.51.0`. The asset is the same static-musl binary family
the host runs, so the Debian image needs nothing added. Baking rtk into the image
is therefore not the fallback it looked like.

**Blocked by:** 04 — Declared environment installed inside the container
(resolved)

**Status:** resolved

- [x] `mise/.config/mise/config.toml` declares `rtk = "latest"`, with a comment
  naming `pi-rtk-optimizer` as the consumer so a future reader knows why an
  output-filter CLI sits in the declaration.
- [x] A sandbox start after the change converges rtk into the toolchain volume,
  and the debug shell (`safe-pi --shell`) resolves it on `PATH`: `which rtk` and
  `rtk --version` both succeed.
- [x] A Pi start inside the sandbox no longer prints the
  `pi-rtk-optimizer: rtk binary unavailable` warning, and a rewritten command
  actually runs through rtk.
- [x] A steady start stays silent: the added tool does not make convergence
  print once the volume holds it.
- [x] rtk's own state (`~/.config/rtk/config.toml`, `~/.local/share/rtk/`) stays
  ephemeral inside the container; nothing is mounted or persisted for it, and the
  extension's own `RTK_DB_PATH` redirection to `/tmp` is left alone.
- [x] The host converges from the same declaration and keeps one provenance for
  rtk: the curl-installed `~/.local/bin/rtk` (0.50.0) is removed, so the host and
  the sandbox both run the mise-installed binary.
- [x] The accepted fail-open behavior is unchanged: an offline first start warns
  twice (convergence, then the extension) and still opens Pi.
- [x] `tests/run --full` prints `FULL GATE: PASS`.

## Comments

### Design (grilling rounds 1-2, 2026-10-09)

Settled decisions behind the ticket:

- **Parity, not silence.** The point is working rewrites inside the sandbox, not
  a quiet start; the sandbox is supposed to inherit the host's Pi setup.
- **Mechanism.** Declare it in the tracked mise configuration. Rejected: mounting
  `~/.local/bin/rtk` (ADR 0002 measured and rejected mounting the host toolchain),
  copying the host binary at wrapper start (same objection plus binary drift), and
  baking it into the image (freezes a `latest` tool into an image layer and forces
  a rebuild where the declaration needs none).
- **rtk only.** No rule machinery, verification code, or per-extension plumbing
  for the general case; the rule ("declare it, never mount it") is already
  recorded in ADR 0002 and needs no new ADR, because reverting this is deleting
  one line.
- **Host provenance.** The declaration is shared, so mise will own rtk on the
  host too. Nothing else on the machine references rtk (no rtk hooks in
  `~/.claude/settings.json`, no reference anywhere in the checkout, and the shell
  history holds only the two `install.sh` lines and one `--version`), and mise's
  install paths already precede `~/.local/bin`, so the curl copy would only ever
  be a drift hazard in shells where mise is not activated.
- **State stays ephemeral.** rtk's savings history and recall database are
  per-machine conveniences the throwaway container does not need; mounting the
  host's rtk directories read-write would hand a bad turn write access to host
  state for no functional gain.
- **Consequences not covered here.** `pi-mac` reads the same declaration, so a
  macOS `mise install` gains rtk too, which is the intent: the extension is
  configured there as well.

### Implemented (2026-10-09)

Integrated as `94d55e7` (`mise/.config/mise/config.toml`: `rtk = "latest"` plus a
comment naming `pi-rtk-optimizer`), on top of `2f1e50d` (this ticket and spec
story 44). No other file changed: no image, wrapper, mount, or
`pi-rtk-optimizer` config.

Evidence:

- **First sandbox start converges it.** With the new declaration mounted at the
  container's mise config path and the real toolchain volume attached, the
  entrypoint installed `rtk@0.51.0` in 2.6 s (`21/21 · installed 1 tool · 20
  already installed`), `command -v rtk` answered
  `/home/sanmoo/.local/share/mise/shims/rtk`, `rtk --version` printed
  `rtk 0.51.0`, and `mise ls rtk` attributed it to `~/.config/mise/config.toml`.
- **Steady start stays silent.** A second start printed only the probe's own
  two lines — no mise output — and `safe-pi --prepare` from the repository
  exited 0 with no convergence output.
- **Wrapper-level end to end.** The wrapper's own resolved invocation
  (`safe-pi --dry-run`, with the trailing `pi -e <reporter>` replaced by a probe
  command) ran in the real container with the wrapper's mounts, environment, and
  volume: `command -v rtk` → the mise shim in the container's toolchain volume,
  `rtk --version` → `rtk 0.51.0`, `rtk ls /usr/local/share/safe-pi` → compact
  proxied output (`herdr-reporter.ts  7.7K`), `mise ls rtk` → 0.51.0 from
  `~/.config/mise/config.toml`.
- **The warning's condition is what was verified.** `pi-rtk-optimizer` probes
  `which rtk` and then `rtk --version` on `session_start` and warns only when
  either fails; both now succeed inside the sandbox, so the warning path is no
  longer reachable. No interactive TUI session was run for this ticket: its
  warning is a `hasUI` notification, and the probe — not the notification — is
  the condition. Its companion evidence is `rtk gain` inside the throwaway
  container reporting a fresh database (1 command), confirming rtk really ran.
- **Host provenance.** `mise install rtk` on the host downloaded
  `rtk-x86_64-unknown-linux-musl.tar.gz`, verified its checksum, and installed
  0.51.0 at `~/.local/share/mise/installs/rtk/latest/rtk`; the curl-installed
  `~/.local/bin/rtk` (0.50.0) was deleted, and a fresh interactive shell now
  resolves `rtk` to the mise install and reports `rtk 0.51.0`. Nothing in the
  checkout or `~/.claude` referenced the old copy.
- **State and fail-open unchanged.** No state directory for rtk is mounted or
  persisted; the extension's `RTK_DB_PATH=/tmp/pi-rtk-optimizer/history.db`
  redirection is untouched; an offline first start still warns twice
  (convergence, then the extension) and opens Pi.

Full gate: `tests/run --full` printed `FULL GATE: PASS` (23 of 23 units) in the
implementation worktree before integration.
