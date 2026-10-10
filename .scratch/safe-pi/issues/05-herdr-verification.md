# 05 — Herdr end-to-end verification

**What to build:** Verification that a sandboxed Pi is indistinguishable from a host Pi inside Herdr, and that the one deliberate difference — a restored pane comes back as a shell instead of an unsandboxed Pi — behaves as documented. This ticket needs the Herdr server restarted, which ends the panes currently running in it, so a human runs it at a moment of their choosing rather than an agent deciding when.

**Blocked by:** 08 — Container-side Herdr integration for the sandbox

**Status:** resolved

- [x] In a Herdr pane, a sandboxed Pi is attributed to Pi and shows `working` during a turn and `idle` after it settles.
- [x] A dangerous command that the approval extension gates shows the pane as `blocked` until it is answered.
- [x] After a Herdr server restart, the pane reopens inside the sandbox in the same conversation, driven by the reporter's self-reported resume command. (Herdr's native `agent_session` field is stored only for official `herdr:*` sources, so it is not expected for a custom-source pane.)
- [x] Restarting the Herdr server and reattaching returns the pane as a plain shell in the saved directory, never as an unsandboxed Pi.
- [x] Continuing from that shell re-enters the sandbox with the same conversation.
- [x] Detaching and reattaching the client keeps the sandboxed Pi running.
- [x] The findings are recorded on this ticket; any behaviour that differs from the usage guide is raised against the guide ticket.

## Comments

### Agent-side verification of items 1–3 (2026-10-08, Herdr 0.9.3)

Items 4–6 remain for a human at a chosen moment, because they restart the Herdr
server. **Items 1–3 fail as implemented.** The sandboxed pane is never
attributed to Pi, so `working`/`blocked`/`idle` and the session reference never
appear.

Setup: `stow pi` installed `safe-pi` at `~/.local/bin/safe-pi` (the image and
`safe-pi-toolchain-u1000` already existed). A scratch directory,
`~/safe-pi-herdr-verify`, was the working directory. In a Herdr pane, `safe-pi`
started the container and Pi's TUI rendered (pane title `π -
safe-pi-herdr-verify`), but:

- Item 1 — `herdr pane get <pane>` reported `agent_status: unknown` with no
  `agent`, and `herdr agent list` never listed the pane.
- Item 2 — `blocked` cannot surface, because there is no attributed agent for
  Herdr to mark blocked. The `permission-gate` extension does emit
  `herdr:blocked` and the integration does consume it; the resulting
  `pane.report_agent` is dropped by the gate below.
- Item 3 — `agent_session` stayed `null` for the pane; nothing points at
  `/run/safe-pi/sessions/…`, container-only or otherwise.

Diagnosis. The container receives `HERDR_ENV=1`,
`HERDR_SOCKET_PATH=/home/sanmoo/.config/herdr/herdr.sock`, and
`HERDR_PANE_ID=<pane>`; the socket is present and connectable from inside the
container. The mounted Herdr-managed integration (`herdr-agent-state.ts`,
integration `pi` v9, source `herdr:pi`) connects, and its `pane.report_agent`
and `pane.report_agent_session` requests are acknowledged with
`{"result":{"type":"ok"}}`, but Herdr does not apply them. Three controls:

- The same `pane.report_agent` request from inside the same container under a
  custom source (`safepi`) is applied immediately: `agent: safepi`,
  `agent_status: working`.
- A `herdr:pi` report for a pane Herdr has not detected as Pi (a plain shell
  pane) is ignored even when sent from the host.
- On Herdr 0.9.3, a custom-source report carrying `agent_session_path`,
  `agent_session_id`, and `resume_argv` is accepted (`ok`) but never populates
  `agent_session`; only official `herdr:*` sources store a native session
  reference. The official docs say custom resume commands need Herdr ≥ 0.10.0.
  **(Superseded — see the correction below: the resume half shipped in 0.9.2
  via `resume_argv`.)**

So Herdr gates the `herdr:pi` source on the pane's detected agent process. A
sandboxed pane's foreground process is `docker`, Herdr never detects Pi, and the
managed integration's reports are discarded. The socket and environment
forwarding are correct; the mounted Herdr-managed integration cannot establish
attribution across the container boundary. The spec's "the wrapper advertises
itself to Herdr as a Pi process" is not implemented anywhere in `safe-pi`.

Also noted: `HERDR_BIN_PATH` is not forwarded and the Herdr binary is not
mounted. The mounted extension uses the socket directly, so this is not the
cause, but a container-side integration following the "Add Herdr support"
recipe (`"$HERDR_BIN_PATH" pane report-agent …`) would need it.

Unrelated finding while converging the toolchain: the declared
`erlang@latest`/`elixir@latest` fail to build inside the image (`configure:
error: No curses library functions found`, with `autoconf` and `libssl-dev`
also missing), so `safe-pi --prepare` exits non-zero and every normal start
re-attempts the failing build (~30 s) before failing open. This contradicts
ticket 04's "a steady start is silent in about 0.3s" and the draft guide's
"Later runs start in about a second".

Raised against:

- 03 — the claimed attribution ("the wrapper's advertised agent identity is
  visible to Herdr for the pane") does not hold; the mounted managed
  integration is not enough.
- 06 — the guide's "Herdr's socket, so the pane still reports working, blocked,
  and idle" is false for the sandbox as built.
- 04 — the erlang/elixir convergence failure and the per-start retry delay.

Items 4–6 still need a human run. Because items 1–3 fail, the ticket is not
satisfied until the attribution gap is fixed, or the contract and guide are
corrected to describe the real behaviour.

### Human verification of items 4–6 (maintainer run)

Run by the maintainer after the agent-side checks, in a sandboxed pane
(`safe-pi` in `~/safe-pi-herdr-verify`). All three passed:

- **Item 6 — detach/reattach.** Detaching the client (`ctrl+a d`) and
  reattaching kept the sandboxed Pi running with the conversation intact.
- **Item 4 — server restart.** After `herdr server stop` and restarting Herdr,
  the pane came back as a plain shell in the saved directory
  (`~/safe-pi-herdr-verify`), never as an unsandboxed Pi. The fail-closed
  restore behaves as documented.
- **Item 5 — continue.** `safe-pi -c` from the restored shell re-entered the
  sandbox and resumed the same conversation.

No deviation from the guide was observed for items 4–6. The items 1–3
deviations above stand: the ticket's first three acceptance criteria are not
met, so the ticket as a whole is not satisfied yet.

### Item 3 is future-gated on Herdr (superseded — see the correction below)

Item 3 (Herdr records a session reference pointing at the container-only
sessions path) cannot pass on the installed Herdr 0.9.3. A custom source
attributes the pane and reports state, but Herdr stores no `agent_session` for
it — only official `herdr:*` integrations do — and 0.9.3 is the newest release.
The session reference becomes achievable with a Herdr that accepts custom-source
session references (documented as ≥ 0.10.0), which does not exist yet. **This
paragraph is superseded by the correction below.** It does not block ticket 08:
state attribution (items 1–2) is fixable now. Decide
whether to keep item 3 as an open criterion pending that release or record it as
an accepted limitation.

### Correction: the resume half shipped in 0.9.2; `agent_session` is native-only

The "≥ 0.10.0" claim in the comments above is wrong, and it made the resume half
look future-gated when it is not.

- Herdr **v0.9.2** (PR #4687, the feature release behind the installed 0.9.3)
  added self-reported resume commands: *"Agents can report their own resume
  command. Herdr then reopens their exact session after a server restart, with
  no built-in integration needed."* The current docs say "Resume commands need
  Herdr 0.9.2 or later" and list two restore paths: a native reference through
  an official `herdr:*` integration, or the agent's own reported resume
  command.
- In `src/agent_resume.rs`, the native `agent_session` path is gated by
  `is_official_agent_source(source, agent)`, which accepts only `herdr:*`
  pairs. That is why a custom-source report never populated `agent_session`: it
  is an intentional authority boundary, not a missing release. The resume
  command travels separately as `ReportedAgentResume`/`resume_argv`, with no
  such gate.

So item 3 is reframed above around the auto-restore via `resume_argv`, which is
answerable now (ticket 07). The literal `agent_session` record is not achievable
for a custom source and is recorded as by-design. Items 1–2 pass on the reporter
from ticket 08; item 3 still needs the restart test once ticket 07/08 wire the
resume command.

### Closed: verification complete (maintainer run, 2026-10-10)

The maintainer ran the live verification on the current build and all seven
criteria are met; the ticket is resolved.

- Items 4–6 were already recorded above. Items 1–3, which failed at the
  2026-10-08 agent run, hold on the shipped reporter: the pane is attributed and
  shows `working`/`idle`, the gated command shows `blocked`, and a restart
  restores inside the sandbox through the self-reported resume command. The
  supporting live evidence is ticket 08's end-to-end Herdr evidence and ticket
  09's live-pane checks; item 3's restore is the reporter resume command from
  ticket 13 with ticket 10's exact-session targeting.
- The deviations raised above are closed: 03 and 04 are resolved, and 06
  retired the usage guide's fail-closed wording.
- `agent_session` stays `null` for a custom-source pane by design
  (`is_official_agent_source` admits only `herdr:*` sources). That is the
  recorded intentional boundary, not an open criterion.
