# 13 — Wire the self-reported resume command into the sandbox reporter

**What to build:** Attach a `resume_argv` to the sandbox reporter's reports so a
Herdr server restart restores the pane *inside the sandbox* instead of failing
closed to a shell. Ticket 07 proved the mechanism on Herdr 0.9.3: a custom
source that holds the pane may attach `resume_argv`, Herdr persists it with the
pane, and after a restart it types the stored command into the restored pane's
shell in the saved cwd. Start from `["safe-pi", "-c"]`; ticket 10 refines the
argument to name the exact session. This ticket also retires the fail-closed
statement in ADR 0002 and the README note, because the pane no longer comes back
as a shell.

**Blocked by:** 07 — Spike: a sandbox that declares its own resume command (resolved)

**Status:** ready-for-agent

- [ ] `safe-pi/herdr-reporter.ts` carries `resume_argv` on its
  `pane.report_agent` / `pane.report_agent_session` requests under source
  `safe-pi`, agent `pi`, and re-reports it when the session changes.
- [ ] The command satisfies Herdr's rules: `safe-pi` first (a bare name),
  at most 64 args / 8 KiB, no apostrophes or control characters.
- [ ] A Herdr server restart in a sandboxed pane comes back inside the sandbox
  (a fresh `safe-pi` container resuming the conversation), not a plain shell and
  never an unsandboxed Pi.
- [ ] The reporter test at the socket seam asserts the reported `resume_argv`,
  and the wrapper/entrypoint contract test still asserts the managed integration
  stays inactive.
- [ ] ADR 0002, the spec's session-restore decision, and the README guide are
  updated from "fail closed" to automatic sandbox resume; the guide's
  symptoms/troubleshooting entries change accordingly.

## Comments

### Proposed by ticket 07 (spike answer)

Ticket 07 exercised a reporter-shaped report on an isolated named session
(`herdr --session spike07`, so the live session was never restarted) and found:

- The custom-source report stores
  `"agent_resume": {"source":"safe-pi","agent":"pi","argv":["safe-pi","-c"]}` in
  `session.json`; the native `agent_session` reference stays `null` by design.
- After a server restart with no client attach, the pane's process tree was
  `zsh → bash ~/.local/bin/safe-pi -c → docker run …`, i.e. the sandbox itself
  came back.
- The command is **typed into the pane's shell**, not `exec`'d, so the first
  token must resolve on the pane shell's `PATH` (`safe-pi` does, at
  `~/.local/bin/safe-pi`).
- There is one resume slot per pane: a newer report from the same source
  replaces it; another source that takes the pane replaces it; a source that
  does not hold the pane gets `resume_not_accepted`.
- A self-reported `resume_argv` is consulted before Herdr's built-in official
  resume table (`persist/restore.rs::pane_restore_startup`).

The one shipped-path change this needs is `baseParams()` in
`safe-pi/herdr-reporter.ts` gaining `resume_argv` (and re-reporting on
`session_start` / `agent_start`). Ticket 07 deliberately did not make it, since
that ticket is a spike and its acceptance says nothing in the shipped path
changes. Ticket 10 owns the exact-session refinement; because the command runs on
the host, the argument must be a host-valid session id (`safe-pi --session
<uuid>`), not the container-only path.
