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

**Status:** ready-for-agent

- [ ] `mise/.config/mise/config.toml` declares `rtk = "latest"`, with a comment
  naming `pi-rtk-optimizer` as the consumer so a future reader knows why an
  output-filter CLI sits in the declaration.
- [ ] A sandbox start after the change converges rtk into the toolchain volume,
  and the debug shell (`safe-pi --shell`) resolves it on `PATH`: `which rtk` and
  `rtk --version` both succeed.
- [ ] A Pi start inside the sandbox no longer prints the
  `pi-rtk-optimizer: rtk binary unavailable` warning, and a rewritten command
  actually runs through rtk.
- [ ] A steady start stays silent: the added tool does not make convergence
  print once the volume holds it.
- [ ] rtk's own state (`~/.config/rtk/config.toml`, `~/.local/share/rtk/`) stays
  ephemeral inside the container; nothing is mounted or persisted for it, and the
  extension's own `RTK_DB_PATH` redirection to `/tmp` is left alone.
- [ ] The host converges from the same declaration and keeps one provenance for
  rtk: the curl-installed `~/.local/bin/rtk` (0.50.0) is removed, so the host and
  the sandbox both run the mise-installed binary.
- [ ] The accepted fail-open behavior is unchanged: an offline first start warns
  twice (convergence, then the extension) and still opens Pi.
- [ ] `tests/run --full` prints `FULL GATE: PASS`.

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
