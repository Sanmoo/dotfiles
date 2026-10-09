# 07 — Spike: a sandbox that declares its own resume command

**What to build:** An executable answer to one question: can a sandboxed Pi tell Herdr how to restore itself, so that a restored pane resumes inside the sandbox instead of failing closed to a shell? The mechanism is Herdr's self-reported resume command (`resume_argv` attached to a `pane.report_agent` or `pane.report_agent_session` report), reported by the sandbox reporter under its own source, with the Herdr-managed integration inactive (ticket 08). This is answerable on the installed Herdr 0.9.3, which includes the 0.9.2 resume-command feature. The ticket is time-boxed and produces an answer, not a shipped path: if it works, it proposes the follow-up that wires it in; if it does not, the fail-closed decision stands unchanged.

**Blocked by:** 03 — Container contract: mounts and environment

**Status:** ready-for-agent

**Type:** prototype

- [ ] The sandbox reporter (ticket 08) attaches a `resume_argv` such as `safe-pi -c` to its reports under its own source, with the Herdr-managed integration inactive. (Exact-session targeting, so a restart reopens the same conversation rather than the newest one in the directory, is ticket 10.)
- [ ] A Herdr server restart is exercised, and the observed outcome — conversation resumed inside a sandbox, or pane returned as a shell — is recorded explicitly.
- [ ] The answer states whether Herdr accepts a `resume_argv` from a custom source on the pane, and how it behaves when more than one source or report carries one.
- [ ] If the mechanism works, a follow-up ticket is proposed; if it does not, the ADR's fail-closed decision is recorded as still standing.
- [ ] Nothing in the shipped path changes as a result of this ticket.

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