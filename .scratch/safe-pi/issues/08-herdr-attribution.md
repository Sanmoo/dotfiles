# 08 — Container-side Herdr integration for the sandbox

**What to build:** A Herdr reporter that runs *inside* the sandbox and reports the sandboxed Pi's state under its own source, so a sandboxed pane is attributed to Pi instead of staying `unknown`. Ticket 05 proved the mounted Herdr-managed integration cannot do this: on Herdr 0.9.3 a `herdr:pi` report is dropped when the pane's foreground process is not a detected Pi, and a sandboxed pane's foreground is `docker`. A report from the same container under a custom source is applied immediately, so the fix is a sandbox-owned reporter, with the Herdr-managed integration neutralised inside the sandbox so the two do not compete. **No Herdr upgrade is needed for this ticket:** state attribution from a custom source works on the installed 0.9.3. The session reference is the one part gated on a future Herdr (≥ 0.10.0) and is documented, not required here.

**Blocked by:** None (can start immediately; the socket mount from 03 is already in place)

**Status:** ready-for-human

- [ ] In a sandboxed pane, `herdr agent list` lists the pane and it shows `working` during a turn and `idle` once it settles.
- [ ] A dangerous command gated by `permission-gate` shows the pane as `blocked` until it is answered, and clears when it is.
- [x] The reporter uses its own source (not `herdr:pi`), and the Herdr-managed integration does not report for the pane, so exactly one source holds it.
- [x] Reports are best-effort: an unreachable socket or a failed report never blocks, slows, or breaks Pi.
- [x] The reporter reports the session reference at the container-only sessions path. The installed Herdr 0.9.3 stores none for a custom source, so the limitation is documented (pending a Herdr that accepts custom-source session references, ≥ 0.10.0); this does not block the state attribution that is this ticket's deliverable.
- [x] The reporter ships with the sandbox (in the image or on a container-only mount) without writing into the host Pi agent directory, which is mounted read-only inside the sandbox.
- [x] A test at the docker/entrypoint seam asserts the reporter is loaded and the managed integration is not; the contract and guide (03/06) are updated to the real behaviour.

## Comments

### Evidence and constraints from ticket 05

- Herdr 0.9.3, integration `pi` v9, socket reachable inside the container, `HERDR_ENV=1`, `HERDR_SOCKET_PATH`, `HERDR_PANE_ID` all forwarded. The managed integration's `pane.report_agent` / `pane.report_agent_session` are acknowledged with `{"result":{"type":"ok"}}` and then ignored.
- The same request from inside the same container under a custom source (`safepi`) is applied at once: `agent: safepi`, `agent_status: working`. It is cleared when the pane returns to an idle shell prompt, which is why the reporter must run for as long as Pi does.
- A `herdr:pi` report for a pane Herdr has not detected as Pi is ignored even from the host, so the gate is the source, not the container.
- On 0.9.3, a custom-source report carrying `agent_session_path`, `agent_session_id`, and `resume_argv` is accepted but never populates `agent_session`; only official `herdr:*` sources store a native session reference. The official docs say custom resume commands need Herdr ≥ 0.10.0, which bounds this ticket and ticket 07.

### Seams to decide during implementation

- Loading: Pi accepts `-e/--extension <path>` (repeatable) and an `extensions` settings key, so a container-only reporter can be loaded explicitly. Decide between shipping it in the image and loading it from a container-only path, versus adding it to a sandbox-only agent overlay.
- Disabling the managed integration: the host `~/.pi/agent/extensions` is mounted read-only and contains `herdr-agent-state.ts`. Decide how to keep it from loading in the sandbox (for example a container-only extensions view) without losing the approval and other host extensions the sandbox needs.
- Relationship to ticket 07: the same reporter is the natural place to declare a resume command once Herdr ≥ 0.10.0 accepts one from a custom source. 07 answers whether that works; this ticket does not depend on it.
- ADR 0002 records "Herdr keeps working because the host integration extension reports state over the mounted socket", which ticket 05 disproved. Revisit that decision record when this lands.

### Implementation (agent-side)

Implemented and validated at the seams; the two end-to-end criteria (a real
sandboxed pane showing `working`/`idle`, and `blocked` while the gate is open)
still need a human run under Herdr.

Ships in the image at `/usr/local/share/safe-pi/herdr-reporter.ts`
(`safe-pi/herdr-reporter.ts`, `COPY`ed by the Dockerfile). It reports over the
mounted socket under source `safe-pi` with `agent: pi`, mapping the same events
the managed integration does: `working` on `agent_start`, `idle` on
`agent_settled`, `blocked` with the gate's message while `herdr:blocked` is
active, and the session reference from `ctx.sessionManager.getSessionFile()`
(the container-only `/run/safe-pi/sessions/...`). Every request is
fire-and-forget with a 500 ms unref'd timeout, so a dead socket never delays Pi.

Disabling the managed integration uses the container-only extensions view. The
wrapper mounts the host extensions read-only at `/run/safe-pi/host-extensions`
and a tmpfs over `$HOME/.pi/agent/extensions`; before Pi starts, the entrypoint
symlinks every host extension except `herdr-agent-state.{ts,js}` into that view
and adds the reporter. Host extensions stay immutable (the view is a tmpfs over
the ro source) and exactly one source holds the pane. Building the view is
best-effort: if it fails, the command still runs.

Evidence:

- `tests/safe-pi-wrapper-test.sh` asserts the ro host-extensions mount at the
  container-only path and the tmpfs over the discovered extensions path.
- `tests/safe-pi-entrypoint-test.sh` runs the real entrypoint against a fixture
  host-extensions directory and asserts the view contains the reporter and
  every host extension but neither `herdr-agent-state.ts` nor `.js`; it also
  checks the image context ships the reporter, that a reporter-only view works,
  that a direct image run does not build the view, and that an unusable view
  still runs Pi. All pass.
- `pi/tests/pi-agent/herdr-reporter.test.ts` drives the reporter over a real
  unix socket and asserts source/agent/pane, `idle`/`working`/`blocked`
  transitions, the container-only `agent_session_path`, state deduplication,
  non-TUI suppression, and that an unreachable socket neither throws nor
  slows the handlers. All pass.
- `shellcheck` is clean on the wrapper, entrypoint, and both shell tests.

The session-reference limitation is documented: the reporter carries
`agent_session_path`, but Herdr 0.9.3 stores nothing for a custom source (only
`herdr:*` sources do), pending a Herdr that accepts custom-source session
references (≥ 0.10.0). The reporter deliberately does not declare a resume
command; that is ticket 07's follow-up. ADR 0002 and the `safe-pi` glossary were
updated, and the 03/06 ticket notes and the draft guide now describe the
sandbox reporter instead of the managed integration.
