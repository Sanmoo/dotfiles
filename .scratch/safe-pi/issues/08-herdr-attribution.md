# 08 — Container-side Herdr integration for the sandbox

**What to build:** A Herdr reporter that runs *inside* the sandbox and reports the sandboxed Pi's state under its own source, so a sandboxed pane is attributed to Pi instead of staying `unknown`. Ticket 05 proved the mounted Herdr-managed integration cannot do this: on Herdr 0.9.3 a `herdr:pi` report is dropped when the pane's foreground process is not a detected Pi, and a sandboxed pane's foreground is `docker`. A report from the same container under a custom source is applied immediately, so the fix is a sandbox-owned reporter, with the Herdr-managed integration neutralised inside the sandbox so the two do not compete. **No Herdr upgrade is needed for this ticket:** state attribution from a custom source works on the installed 0.9.3. The session reference is the one part gated on a future Herdr (≥ 0.10.0) and is documented, not required here.

**Blocked by:** None (can start immediately; the socket mount from 03 is already in place)

**Status:** ready-for-agent

- [ ] In a sandboxed pane, `herdr agent list` lists the pane and it shows `working` during a turn and `idle` once it settles.
- [ ] A dangerous command gated by `permission-gate` shows the pane as `blocked` until it is answered, and clears when it is.
- [ ] The reporter uses its own source (not `herdr:pi`), and the Herdr-managed integration does not report for the pane, so exactly one source holds it.
- [ ] Reports are best-effort: an unreachable socket or a failed report never blocks, slows, or breaks Pi.
- [ ] The reporter reports the session reference at the container-only sessions path. The installed Herdr 0.9.3 stores none for a custom source, so the limitation is documented (pending a Herdr that accepts custom-source session references, ≥ 0.10.0); this does not block the state attribution that is this ticket's deliverable.
- [ ] The reporter ships with the sandbox (in the image or on a container-only mount) without writing into the host Pi agent directory, which is mounted read-only inside the sandbox.
- [ ] A test at the docker/entrypoint seam asserts the reporter is loaded and the managed integration is not; the contract and guide (03/06) are updated to the real behaviour.

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
