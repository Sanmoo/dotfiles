# 05 — Herdr end-to-end verification

**What to build:** Verification that a sandboxed Pi is indistinguishable from a host Pi inside Herdr, and that the one deliberate difference — a restored pane comes back as a shell instead of an unsandboxed Pi — behaves as documented. This ticket needs the Herdr server restarted, which ends the panes currently running in it, so a human runs it at a moment of their choosing rather than an agent deciding when.

**Blocked by:** 04 — Declared environment installed inside the container

**Status:** ready-for-human

- [ ] In a Herdr pane, a sandboxed Pi is attributed to Pi and shows `working` during a turn and `idle` after it settles.
- [ ] A dangerous command that the approval extension gates shows the pane as `blocked` until it is answered.
- [ ] Herdr records a session reference for the pane, and it points at the container-only sessions path.
- [ ] Restarting the Herdr server and reattaching returns the pane as a plain shell in the saved directory, never as an unsandboxed Pi.
- [ ] Continuing from that shell re-enters the sandbox with the same conversation.
- [ ] Detaching and reattaching the client keeps the sandboxed Pi running.
- [ ] The findings are recorded on this ticket; any behaviour that differs from the usage guide is raised against the guide ticket.

## Comments
