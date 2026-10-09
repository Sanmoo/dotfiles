# 07 — Spike: a sandbox that declares its own resume command

**What to build:** An executable answer to one question: can a sandboxed Pi tell Herdr how to restore itself, so that a restored pane resumes inside the sandbox instead of failing closed to a shell? The mechanism is Herdr's self-reported resume command (`resume_argv` attached to a `pane.report_agent` or `pane.report_agent_session` report), reported by the sandbox reporter under its own source, with the Herdr-managed integration inactive (ticket 08). This is answerable on the installed Herdr 0.9.3, which includes the 0.9.2 resume-command feature. The ticket is time-boxed and produces an answer, not a shipped path: if it works, it proposes the follow-up that wires it in; if it does not, the fail-closed decision stands unchanged.

**Blocked by:** 03 — Container contract: mounts and environment (resolved)

**Status:** resolved

**Type:** prototype

- [x] The sandbox reporter (ticket 08) attaches a `resume_argv` such as `safe-pi -c` to its reports under its own source, with the Herdr-managed integration inactive. (Exact-session targeting, so a restart reopens the same conversation rather than the newest one in the directory, is ticket 10.)
- [x] A Herdr server restart is exercised, and the observed outcome — conversation resumed inside a sandbox, or pane returned as a shell — is recorded explicitly.
- [x] The answer states whether Herdr accepts a `resume_argv` from a custom source on the pane, and how it behaves when more than one source or report carries one.
- [x] If the mechanism works, a follow-up ticket is proposed; if it does not, the ADR's fail-closed decision is recorded as still standing.
- [x] Nothing in the shipped path changes as a result of this ticket.

## Comments

Ticket 05 pre-empted part of this spike on Herdr 0.9.3. A container-side
integration under a custom source does get the pane attributed and reports
state (`working`/`blocked`/`idle`), but a report carrying `agent_session_path`,
`agent_session_id`, and `resume_argv` is accepted (`ok`) and never populates
`agent_session`; only official `herdr:*` sources store a native session
reference. The official docs put custom resume commands at Herdr ≥ 0.10.0, so
the resume half of this spike cannot be answered on the installed 0.9.3. The
state half is now ticket 08. **(Superseded — see below: the resume half shipped
in Herdr 0.9.2.)**

### Unblocked: resume commands shipped in 0.9.2 (research finding)

The "≥ 0.10.0" note above is wrong and is superseded. Herdr **0.9.2** added
self-reported resume commands (PR #4687): attach `resume_argv` to a
`pane.report_agent` or `pane.report_agent_session` report and Herdr runs it in
the restored pane, provided the source already holds the pane. The command's
first token must be a plain command name on the host PATH (`safe-pi`
qualifies), at most 64 args / 8 KiB, with no apostrophes or control characters.
The current docs say "Resume commands need Herdr 0.9.2 or later".

`agent_session` is a different, native mechanism, gated by
`is_official_agent_source` to `herdr:*` sources in `src/agent_resume.rs`, which
is why ticket 05 saw it stay `null` for a custom source. That gate is
intentional; the `resume_argv` path is what answers this spike.

So the spike is answerable now, and ticket 08's reporter is the place to attach
the resume command. The first form to test is `["safe-pi", "-c"]`; ticket 10
carries the requirement (and open questions) for naming the exact session
instead of the newest one in the directory.

## Answer

**The mechanism works on the installed Herdr 0.9.3.** A custom source that holds
the pane may attach a `resume_argv`; Herdr persists it with the pane and, after a
server restart, spawns the pane's shell in the saved cwd and **types the stored
command into it**. No client attach was needed for the named session tested. The
restored command runs the same `safe-pi`, so the pane comes back *inside the
sandbox* — the isolation boundary is preserved, never an unsandboxed Pi. Nothing
in the shipped path changed: this answer adds no code.

### Setup (live session untouched)

Everything ran against an **isolated named session** (`herdr --session spike07`),
never the default session, so no server restart ended the live panes. A scratch
pane in `/tmp/spike07/work` and `/tmp/spike07/work2` received reports under
`--source safe-pi --agent pi` — the reporter's own source and agent. The
reporter-shaped requests (`pane.report_agent`, params
`pane_id`/`source`/`agent`/`seq`/`state`/`resume_argv`, the exact shape
`herdr-reporter.ts` emits) were sent with
`herdr pane report-agent … -- safe-pi -c`. The Herdr-managed integration was
never active, matching ticket 08's environment.

### Observed

- The report is accepted (`ok`, exit 0), and it is **persisted**:
  `session.json` carries
  `"agent_resume": {"source":"safe-pi","agent":"pi","argv":["safe-pi","-c"]}`.
  This is the key difference from the native mechanism: the custom source does
  store the resume command, even though `agent_session` stays `null` (the
  `is_official_agent_source` gate ticket 05 found).
- After `herdr session stop spike07` and a headless
  `herdr --session spike07 server`, the pane's process tree was
  `zsh → bash /home/sanmoo/.local/bin/safe-pi -c → docker run --rm --interactive
  --tty --workdir /tmp/spike07/work …`: the restored pane launched a real
  `safe-pi` sandbox with the stored command. A second restart with a probe
  script (`spike07-probe A2`) on `PATH` recorded `argv: A2`, `cwd:
  /tmp/spike07/work2`, and the pane shell's `PATH`, confirming the saved
  directory and that resolution goes through the pane shell.
- Rejection paths behave as documented: a path as the first token or an
  apostrophe in an argument returns `invalid_resume_argv`; a source that does not
  hold the pane returns `resume_not_accepted`.

### Answers to the acceptance questions

1. **Does Herdr accept a `resume_argv` from a custom source on the pane?** Yes.
   The source must hold the pane (`pane.report_agent` first), and `resume_argv[0]`
   must be a bare command name on the pane shell's `PATH`. `safe-pi` qualifies
   (`~/.local/bin/safe-pi`).
2. **More than one source or report.** There is exactly **one slot per pane**
   (`TerminalState::reported_resume`). A newer report from the same source
   replaces the stored command (last accepted wins, guarded by `seq`: a report
   with no `seq` after one with a `seq` is not newer and is ignored). A second
   source that takes the pane with its own `pane.report_agent` replaces the
   command; `reconcile_reported_resume` drops the old one once a different
   agent/source holds the pane. A source that does not hold the pane cannot
   record a command at all (`resume_not_accepted`).
3. **Precedence.** A self-reported `resume_argv` is consulted **before** Herdr's
   built-in official resume table (`persist/restore.rs::pane_restore_startup`),
   so the sandbox command wins for the pane. `[session]
   resume_agents_on_restore = false` disables both.
4. **How it runs.** Restore spawns the pane's default shell and writes
   `shell_command_from_argv(argv) + "\r"` into the PTY (POSIX-quoted). It is a
   typed command, not an `exec`, which is why the first token must resolve on the
   shell's `PATH` and why a stub only in a non-`PATH` directory is not picked up.
5. **Persistence scope.** The command is kept while the reporter holds the
   pane; an explicit `pane.release_agent`, a different agent taking the pane, or
   observing the agent's process exit clears it. A fresh report from the
   reporter after the sandbox restarts re-establishes it.

### What is left for the follow-up

The shipped `safe-pi/herdr-reporter.ts` deliberately does not declare a resume
command (ticket 08), so its `sendRequest` `baseParams()` has to gain
`resume_argv`. That is the follow-up: **ticket 13 — wire the self-reported resume
command into the sandbox reporter** (starting from `["safe-pi", "-c"]`, refined
to the exact session by ticket 10), which also rewrites ADR 0002's "left to fail
closed" sentence and the README's fail-closed note. Per this ticket's scope,
those shipped-path changes are not made here.

Open item handed to ticket 10: because the command runs on the **host** in the
saved cwd, a container-only session path is invalid there; the exact-session
argument should be the session id (UUID) forwarded as `safe-pi --session <id>`, not
the `/run/safe-pi/sessions/…` path.