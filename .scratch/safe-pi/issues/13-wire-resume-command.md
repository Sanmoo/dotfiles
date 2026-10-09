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

**Status:** resolved

- [x] `safe-pi/herdr-reporter.ts` carries `resume_argv` on its
  `pane.report_agent` / `pane.report_agent_session` requests under source
  `safe-pi`, agent `pi`, and re-reports it when the session changes.
- [x] The command satisfies Herdr's rules: `safe-pi` first (a bare name),
  at most 64 args / 8 KiB, no apostrophes or control characters.
- [x] A Herdr server restart in a sandboxed pane comes back inside the sandbox
  (a fresh `safe-pi` container resuming the conversation), not a plain shell and
  never an unsandboxed Pi.
- [x] The reporter test at the socket seam asserts the reported `resume_argv`,
  and the wrapper/entrypoint contract test still asserts the managed integration
  stays inactive.
- [x] ADR 0002, the spec's session-restore decision, and the README guide are
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

### Implemented (2026-10-09)

Integrated as `a98dfa4` (implementation) on top of `ef51f92` (the spec and
glossary wording), with `35fd880` retiring the problem statement's and user
stories 18-19's remaining fail-closed wording. `baseParams()` now carries
`resume_argv: ["safe-pi", "-c"]`, so both `pane.report_agent` and
`pane.report_agent_session` reports under source `safe-pi` / agent `pi` declare
it, and a changed session re-states it. The reporter's header doc and the new
constant's JSDoc state Herdr's rules for a self-reported command.

Evidence:

- `pi/tests/pi-agent/herdr-reporter.test.ts` asserts the reported `resume_argv`
on both request kinds, its re-statement when the session file changes, and that
every report keeps Herdr's rules (bare first token, `<= 64` args / 8 KiB, no
apostrophes or control characters), so ticket 10's refinement cannot silently
break a rule. `tests/safe-pi-wrapper-test.sh` is unchanged and still asserts
`--env SAFE_PI_HERDR_*` with `assert_no_log "--env HERDR_"`, so the managed
integration stays inactive.
- End-to-end against an isolated named Herdr session (`herdr --session
safe-pi13`, never the live session): the shipped reporter, run against a fresh
pane's socket, made Herdr attribute the pane to `pi` and persist
`"agent_resume": {"source": "safe-pi", "agent": "pi", "argv": ["safe-pi",
"-c"]}` in the session file. After `herdr session stop safe-pi13` and a
headless restart, that pane's process tree was `bash
~/.local/bin/safe-pi -c -> docker run --rm --interactive --tty --workdir
<saved cwd> ... safe-pi:current-u1000 pi -e
/usr/local/share/safe-pi/herdr-reporter.ts -c` — the pane came back inside a
fresh sandbox in its saved directory, not a plain shell and never an
unsandboxed Pi. The run and the method are recorded in ADR 0002. The isolated
session and its containers were removed afterwards; the live server was never
restarted.
- Historical note: the image used for the restart still carried the pre-change
reporter, so the *restored* sandbox did not re-declare the command. That does
not affect the criterion (the stored command — the shipped reporter's — drove
the restore), and a rebuilt image carries the new reporter.

Full gate: `tests/run --full` printed `FULL GATE: PASS` (23 of 23 units).

Ticket 05's restart item stays open and human-owned: it restarts the *live*
Herdr server, which ends the panes currently running in it. This ticket's
verification used an isolated session precisely to avoid that.
