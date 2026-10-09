# 09 — Releasing the pane when the sandboxed Pi exits

**What to build:** A sandboxed pane must stop being attributed as a running agent when the Pi process inside the container exits (for example after Ctrl-C twice), not only when the pane is closed. Two things are wrong today, and both are fixed in the sandbox reporter: it never sends `pane.release_agent`, and it reports the agent label `pi`, which disarms Herdr's own idle-shell safety net. The reporter gains an explicit release on quit, and it reports an agent label Herdr does not recognize so the safety net arms for exits that produce no shutdown event.

**Blocked by:** 08 — Container-side Herdr integration for the sandbox (resolved)

**Status:** ready-for-human

## What is known

- State is reported by the sandbox reporter (`safe-pi/herdr-reporter.ts`) under source `safe-pi`. It reports `working`/`blocked`/`idle` only; it does **not** send `pane.release_agent`, and it has no `session_shutdown` handler.
- **Root cause.** Herdr arms its idle-shell safety net only for a self-reported agent whose label it does not recognize by process: `self_reported_agent_active()` in `src/terminal/state.rs` tests `parse_agent_label(&authority.agent_label).is_none()`. The reporter reports `agent: "pi"`, and `parse_agent_label("pi")` resolves to `Agent::Pi`, so the safety net never ran and the pane stayed attributed. Herdr's own test `shell_return_keeps_agents_herdr_recognizes_by_process` asserts exactly this. Ticket 05's experiment that did clear used the label `safepi`; ticket 08's switch to `pi` is what disarmed it.
- **Pi does quit.** In the TUI, `handleCtrlC()` treats a second Ctrl-C within 500 ms as quit → `shutdown()` → `await runtimeHost.dispose()`, which emits `session_shutdown` with `reason: "quit"` and is awaited by the extension runner → writes the resume hint → `process.exit(0)`. Pi is PID 1 in the container (the entrypoint `exec`s it), so the container and `docker run` end and the pane returns to its shell. Ctrl-D, `/quit`, and SIGTERM/SIGHUP take the same dispose path; session replacement emits `resume`/`new`/`fork`, and extension reload emits `reload`.
- The reporter's `sendRequest` is fire-and-forget, so a release from `session_shutdown` must be awaited (bounded) or `process.exit(0)` drops it.
- `pane.release_agent` with source `safe-pi` is accepted: it is not an official source pair, and the label matches the current authority. It clears the pane's name, state, and stored resume command.
- Herdr accepts a per-source `pane.report_metadata` `display_agent` with no authority requirement, and the sidebar/border label prefers `display_agent` over the agent label, so a custom agent label can still display as `Pi`. `herdr agent list` prints raw JSON, so it shows `"agent": "safe-pi"` alongside `"display_agent": "Pi"`.
- Re-entry needs no code: Herdr's `clear_self_reported_agent` ignores a shell-return signal older than the current authority, so a fresh report after `safe-pi -c` survives a late safety-net clear.
- The host wrapper knows the pane id after `docker run` returns but is deliberately not used: it would be a second writer on the same source, needing `seq` coordination, and only the reporter knows the difference between quitting and switching sessions.
- The reporter ships in the image (`COPY`ed by the Dockerfile) and the wrapper rebuilds a cached image only when the `safe-pi.entrypoint` label changes, so this change bumps the label: ticket 08 flagged that ticket 10 shipped a new reporter without bumping it, leaving a cached image serving the superseded one.

## Acceptance criteria

- [x] On `session_shutdown` with `reason === "quit"`, and only when the reporter holds the pane (TUI mode), the reporter sends `pane.release_agent` for source `safe-pi` and its agent label, and the report reaches Herdr before `process.exit(0)`.
- [x] The reporter never releases on `reload`, `resume`, `new`, or `fork`; those are session replacements where the new session reports instead.
- [x] The reported agent label is one Herdr does not recognize (`safe-pi`), and `pane.report_metadata` sets `display_agent: "Pi"`, so the sidebar and border still read `Pi`.
- [x] The release is best-effort: an unreachable socket is swallowed and costs at most 250 ms at quit; it never throws, never blocks longer, and never breaks Pi.
- [ ] Reproduction on a real pane: Ctrl-C twice in `safe-pi`, then `herdr agent list` no longer lists the pane, without closing it.
- [ ] A sandbox that dies without a shutdown event (SIGKILL/OOM/daemon stop) also clears, via Herdr's idle-shell safety net, about a second after the pane's shell returns.
- [ ] Re-entry (`safe-pi -c`) still re-attributes the pane.
- [x] The host wrapper gains no release logic: the reporter stays the only writer on the `safe-pi` source. The image's `safe-pi.entrypoint` label is bumped so a cached image rebuilds with the new reporter.
- [x] `pi/tests/pi-agent/herdr-reporter.test.ts` covers the release trigger, the non-triggers, the bounded await, and the agent-label constant; `tests/run --full` ends in `FULL GATE: PASS`.

The three unticked boxes need a live Herdr pane: two are the end-to-end
reproduction, and re-entry is Herdr's own newer-claim guard rather than
reporter code.

## Comments

### Reported (maintainer)

After Ctrl-C twice in `safe-pi`, Herdr still considers the agent running. It only
leaves the running-agents list when the pane is closed. Expected: it ends when
the Pi process inside the container terminates.

### Resolved by a grilling session (agent)

The ticket's four open questions were answered from Pi's and Herdr 0.9.3's
source, and the design was settled:

- The container does exit on Ctrl-C twice, and Pi does emit `session_shutdown`
  (reason `quit`); the reporter is alive but had no handler.
- The idle-shell safety net did not clear the pane because the `agent: "pi"`
  label disarms it; ticket 05's clearing experiment used `safepi`.
- The release belongs to the reporter, not the host wrapper.
- `safe-pi` becomes the reported agent label (arming the safety net), with
  `display_agent: "Pi"` keeping the visible name; the explicit release covers the
  normal quit immediately.

Recorded in ADR 0004 and the `CONTEXT.md` terms "Pane release", "Idle-shell
safety net", and the updated "Sandbox reporter".

### Implementation (agent, commit 15f794d)

The reporter now sends `pane.release_agent` from a `session_shutdown` handler
that releases only on `reason === "quit"` and only for a TUI root session, and
awaits the send with a 250 ms cap (`sendRequestAndWait`); the release shares the
`authorityParams()` helper with the state and metadata reports, and one `send()`
backs both the fire-and-forget and awaited paths. It reports agent label
`safe-pi` with `pane.report_metadata` `display_agent: "Pi"` so Herdr's
idle-shell safety net stays armed. The image's `safe-pi.entrypoint` label went
to `5` (Dockerfile, wrapper comparison, wrapper-test stub) so a cached image
rebuilds with the new reporter.

Evidence: `pi/tests/pi-agent/herdr-reporter.test.ts` grew to 17 tests (release
on quit, the four non-triggers, headless, the bounded deadline against a silent
server, the label and display metadata); `tests/run --full` ended in
`FULL GATE: PASS` (23/23 units); `shellcheck` is clean on the wrapper, the
entrypoint, and the wrapper test.

The two-axis review found no spec gaps and no hard standards breach; its
judgement calls (the duplicated socket send, the hand-built params, `release`
renamed to `releasePane`, a tighter deadline assertion) were applied in commit
15f794d.

Remaining: the live-pane reproduction and the SIGKILL safety-net check, plus
re-entry, which need a real Herdr pane and are left for a human.
