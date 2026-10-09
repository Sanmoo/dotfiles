# A sandboxed pane is released by its reporter, and its agent label keeps Herdr's idle-shell safety net armed

ADR 0002 gave the sandbox a reporter under source `safe-pi` that reports state, a session reference, and a self-reported resume command, and it reported the agent label `pi`. On Herdr 0.9.3 a sandboxed pane therefore stayed in `herdr agent list` after the sandboxed Pi exited, and only closing the pane cleared it: Herdr's idle-shell safety net is armed only for a self-reported agent whose label Herdr does not recognize by process (`self_reported_agent_active()` tests `parse_agent_label(label).is_none()`), and `pi` resolves to a recognized agent, so the fallback never ran. Ticket 05 had observed the fallback clearing a `safepi`-labelled report; ticket 08's switch to `pi` is what disarmed it. The decision is that the reporter releases the pane itself and reports an agent label Herdr does not recognize:

- On `session_shutdown` with `reason: "quit"` — Ctrl-C twice, Ctrl-D, `/quit`, and SIGTERM/SIGHUP all reach it — the reporter sends `pane.release_agent` for its source and label and awaits the send with a 250 ms cap, so `process.exit(0)` cannot drop it. It never releases on `reload`, `resume`, `new`, or `fork`, which are session replacements where the new session reports instead.
- The reported agent label becomes `safe-pi` (matching the source), and the reporter sends `pane.report_metadata` with `display_agent: "Pi"`, so the sidebar and border keep showing Pi while the safety net stays armed for exits that produce no shutdown event (SIGKILL, OOM-kill, a stopped daemon).
- The host wrapper stays a Docker launcher and does not speak to Herdr.

## Considered Options

- **Keep `agent: "pi"` and rely only on the explicit release.** Rejected: every exit that produces no `session_shutdown` would leave the pane attributed until it was closed, which is the reported symptom.
- **Keep `agent: "pi"` and let the host wrapper release after `docker run` returns.** Rejected: the wrapper would become a second Herdr writer on the same source, needing `seq` coordination with the reporter, and the reporter is the only party that can tell a quit from a session replacement.
- **Rely only on the safety net by changing the label, with no explicit release.** Rejected: it clears only after the pane's shell is seen idle, about a second after a normal quit, which leaves the pane attributed for that window.
- **Accept `safe-pi` as the visible agent name.** Rejected: the sandbox is a Pi, the spec and `CONTEXT.md` attribute the pane to Pi, and `pane.report_metadata` already separates the label from the displayed name.

## Consequences

- `herdr agent list` shows `"agent": "safe-pi"` with `"display_agent": "Pi"`; the sidebar and border read Pi. Automation matching the raw `agent` field must match `safe-pi`.
- Herdr's idle-shell safety net now applies to the pane, so a sandbox that dies without a shutdown event clears about a second after the pane's shell returns. A fresh report made after that signal survives Herdr's newer-claim guard, so `safe-pi -c` re-attributes normally.
- The release is best-effort: an unreachable socket costs at most 250 ms at quit and is otherwise swallowed.
- The label is load-bearing for the safety net, not cosmetic: reverting it to `pi` would silently re-disarm the fallback while state reporting still looked correct.
