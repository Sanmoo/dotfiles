# 08 — Container-side Herdr integration for the sandbox

**What to build:** A Herdr reporter that runs *inside* the sandbox and reports the sandboxed Pi's state under its own source, so a sandboxed pane is attributed to Pi instead of staying `unknown`. Ticket 05 proved the mounted Herdr-managed integration cannot do this: on Herdr 0.9.3 a `herdr:pi` report is dropped when the pane's foreground process is not a detected Pi, and a sandboxed pane's foreground is `docker`. A report from the same container under a custom source is applied immediately, so the fix is a sandbox-owned reporter, with the Herdr-managed integration neutralised inside the sandbox so the two do not compete. **No Herdr upgrade is needed for this ticket:** state attribution from a custom source works on the installed 0.9.3. Herdr's native `agent_session` field is stored only for official `herdr:*` sources, so a custom source cannot set it by design; automatic restore uses a self-reported `resume_argv`, shipped in Herdr 0.9.2 and left to ticket 07.

**Blocked by:** None (can start immediately; the socket mount from 03 is already in place)

**Status:** ready-for-human

- [ ] In a sandboxed pane, `herdr agent list` lists the pane and it shows `working` during a turn and `idle` once it settles.
- [ ] A dangerous command gated by `permission-gate` shows the pane as `blocked` until it is answered, and clears when it is.
- [x] The reporter uses its own source (not `herdr:pi`), and the Herdr-managed integration does not report for the pane, so exactly one source holds it.
- [x] Reports are best-effort: an unreachable socket or a failed report never blocks, slows, or breaks Pi.
- [x] The reporter reports the session reference at the container-only sessions path. Herdr stores `agent_session` only for official `herdr:*` sources (`is_official_agent_source` in `src/agent_resume.rs`), so a custom source never populates it; this is by design and documented. Automatic restore uses a self-reported `resume_argv` (Herdr ≥ 0.9.2), which is ticket 07's follow-up.
- [x] The reporter ships with the sandbox (in the image or on a container-only mount) without writing into the host Pi agent directory, which is mounted read-only inside the sandbox.
- [x] A test at the docker/entrypoint seam asserts the reporter is loaded and the managed integration is not; the contract and guide (03/06) are updated to the real behaviour.

## Comments

### Evidence and constraints from ticket 05

- Herdr 0.9.3, integration `pi` v9, socket reachable inside the container, `HERDR_ENV=1`, `HERDR_SOCKET_PATH`, `HERDR_PANE_ID` all forwarded. The managed integration's `pane.report_agent` / `pane.report_agent_session` are acknowledged with `{"result":{"type":"ok"}}` and then ignored.
- The same request from inside the same container under a custom source (`safepi`) is applied at once: `agent: safepi`, `agent_status: working`. It is cleared when the pane returns to an idle shell prompt, which is why the reporter must run for as long as Pi does.
- A `herdr:pi` report for a pane Herdr has not detected as Pi is ignored even from the host, so the gate is the source, not the container.
- On 0.9.3, a custom-source report carrying `agent_session_path`, `agent_session_id`, and `resume_argv` is accepted but never populates `agent_session`; only official `herdr:*` sources store a native session reference. That gate is `is_official_agent_source` in `src/agent_resume.rs` — intentional, not a missing release. Custom resume commands actually shipped in Herdr 0.9.2 via `resume_argv` (PR #4687); see the correction below.

### Seams to decide during implementation

- Loading: Pi accepts `-e/--extension <path>` (repeatable) and an `extensions` settings key, so a container-only reporter can be loaded explicitly. Decide between shipping it in the image and loading it from a container-only path, versus adding it to a sandbox-only agent overlay.
- Disabling the managed integration: the host `~/.pi/agent/extensions` is mounted read-only and contains `herdr-agent-state.ts`. Decide how to keep it from loading in the sandbox (for example a container-only extensions view) without losing the approval and other host extensions the sandbox needs.
- Relationship to ticket 07: the same reporter is the natural place to declare a resume command. Herdr ≥ 0.9.2 (installed 0.9.3) already accepts a custom-source `resume_argv`, so 07 answers with a restart test; this ticket does not depend on it.
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

Disabling the managed integration withholds the variables that activate it,
rather than remounting host extensions. The host extensions stay mounted
read-only at their own path, `HERDR_ENV`/`HERDR_SOCKET_PATH`/`HERDR_PANE_ID` are
not forwarded, and the reporter is loaded from the image with Pi's `-e` flag,
receiving the socket and pane under `SAFE_PI_HERDR_SOCKET_PATH` and
`SAFE_PI_HERDR_PANE_ID`. The managed integration is therefore loaded but
inactive — and Herdr would drop a `herdr:pi` report for a `docker` foreground
anyway — so exactly one source (`safe-pi`) owns the pane.

An earlier revision built a container-only extensions view instead, remounting
the host extensions at `/run/safe-pi/host-extensions`. Real-container validation
disproved it twice: BuildKit's `COPY --chmod=0644` also chmodded the
implicitly-created reporter directory to a non-traversable mode, and the host
extensions are relative symlinks (`../../../dev/...`) that dangle once
remounted at a different depth. Both are recorded because they are why the
shipped mechanism is the env neutralisation.

Evidence:

- An image built before the reporter (no label or `safe-pi.entrypoint="1"`) is
  stale and rebuilt on next use, since it has no reporter to load. The label is
  bumped to `"2"` and `tests/safe-pi-wrapper-test.sh` asserts the old image is
  rebuilt.
- `tests/safe-pi-wrapper-test.sh` asserts the host extensions mount at their
  own read-only path, the `SAFE_PI_HERDR_SOCKET_PATH`/`SAFE_PI_HERDR_PANE_ID`
  forwarding, the absence of `--env HERDR_*`, and `pi -e
  /usr/local/share/safe-pi/herdr-reporter.ts` in the run invocation.
- `tests/safe-pi-entrypoint-test.sh` asserts the image build context ships the
  reporter and creates its directory traversable (the BuildKit `--chmod` trap).
  All pass.
- `pi/tests/pi-agent/herdr-reporter.test.ts` drives the reporter over a real
  unix socket and asserts source/agent/pane, `idle`/`working`/`blocked`
  transitions, the container-only `agent_session_path`, state deduplication,
  non-TUI suppression, and that an unreachable socket neither throws nor
  slows the handlers. All pass.
- Real-container check (not part of the suite): the image was built, the
  sandbox user could read the reporter, and the shipped `.ts` loaded under the
  image's Node and emitted exactly `pane.report_agent`/`pane.report_agent_session`
  with source `safe-pi`, agent `pi`, states `idle`/`working`/`blocked`/`working`,
  and the container-only session path.
- `shellcheck` is clean on the wrapper, entrypoint, and both shell tests.

The session-reference limitation is documented: the reporter carries
`agent_session_path`, but Herdr stores `agent_session` only for official
`herdr:*` sources — `is_official_agent_source` is an intentional authority
boundary, not a pending release. The reporter deliberately does not declare a
resume command; Herdr has accepted a custom-source `resume_argv` since 0.9.2, so
that is ticket 07's follow-up. ADR 0002 and the `safe-pi` glossary were
updated, and the 03/06 ticket notes and the draft guide now describe the
sandbox reporter instead of the managed integration.
