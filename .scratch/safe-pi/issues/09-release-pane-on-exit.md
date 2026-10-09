# 09 — Releasing the pane when the sandboxed Pi exits

**What to build:** A sandboxed pane must stop being attributed as a running agent when the Pi process inside the container exits (for example after Ctrl-C twice), not only when the pane is closed. Today `herdr agent list` keeps showing the pane as a running agent after the sandboxed Pi is gone; closing the pane is the only thing that clears it.

**Blocked by:** 08 — Container-side Herdr integration for the sandbox (the reporter whose exit behaviour this changes)

**Status:** needs-info

- [ ] Reproduction: in a Herdr pane, start `safe-pi`, press Ctrl-C twice; `herdr agent list` still lists the pane, and only closing the pane clears it.
- [ ] Expected: once the Pi process in the container ends, the pane leaves the agent list without closing it.

## What is known

- State is reported by the sandbox reporter (`safe-pi/herdr-reporter.ts`) under source `safe-pi`. It reports `working`/`blocked`/`idle` only; it does **not** send `pane.release_agent`, and it has no `session_shutdown` handler.
- The Herdr docs describe a release report for exactly this case ("Only release when the user actually quits") and an idle-shell safety net ("If your agent exits without releasing, Herdr notices once the pane is back at its idle shell prompt"). The pane's foreground process is `docker`, so it is unclear which path applies here.
- The host wrapper knows the pane id after `docker run` returns, but it forwards the socket/pane to the container under `SAFE_PI_HERDR_*` and withholds `HERDR_*`.

## Open questions (why this is `needs-info`)

- Does the container / `docker run` process actually exit on Ctrl-C twice, or does something (entrypoint, mise, TTY handling) linger?
- Does Pi emit `session_shutdown` on Ctrl-C twice, and is the reporter still alive to send `pane.release_agent` then?
- If the container does exit, why does the idle-shell safety net not clear the agent — because the pane never returns to a prompt, or because a stale report keeps arriving?
- Should the release be sent by the reporter on shutdown, by the host wrapper after `docker run` returns (it has the pane id), or both — and what happens when `safe-pi -c` re-enters the same pane afterwards?

## Acceptance criteria (draft, pending the answers)

- [ ] Ctrl-C twice in a sandboxed Pi clears the pane from `herdr agent list` without closing the pane.
- [ ] The release is best-effort and never blocks or breaks Pi or the wrapper.
- [ ] Re-entry (`safe-pi -c`) still re-attributes the pane.

## Comments

### Reported (maintainer)

After Ctrl-C twice in `safe-pi`, Herdr still considers the agent running. It only
leaves the running-agents list when the pane is closed. Expected: it ends when
the Pi process inside the container terminates.
