# 06 — Usage guide in the README

**What to build:** The draft usage guide becomes a section of the repository README, in that document's existing style and prose, cross-referenced from the Herdr section, and the draft file is deleted. Every recipe in the guide is exercised against the built command before the ticket is done, and the troubleshooting table describes behaviour that was actually observed rather than behaviour that was intended.

**Blocked by:** 04 — Declared environment installed inside the container

**Status:** ready-for-agent

- [ ] The README section replaces the draft, and the draft file no longer exists.
- [ ] Every recipe in the guide works as written: each flag is accepted and produces the described effect.
- [ ] The limitations the guide names are the ones that exist: fail-closed restore, read-only extensions and packages, convergence that fails open, and the credential caveat.
- [ ] Each troubleshooting row corresponds to a behaviour observed while verifying tickets 01–05.
- [ ] The Herdr section cross-references the guide.

## Comments

The draft guide is wrong about Herdr reporting. Ticket 05 found that a
sandboxed pane is never attributed to Pi (Herdr 0.9.3 drops the mounted managed
integration's reports because the pane's foreground process is `docker`), so
"Herdr's socket, so the pane still reports `working`, `blocked`, and `idle`" is
not true as built. The troubleshooting row "Herdr shows the pane as a plain
terminal" is also closer to the normal case than the exception. The guide's
first-run timing likewise needs the erlang/elixir failure captured: the declared
toolchain does not converge in the image, so starts are not "about a second".
See ticket 05 for evidence.

### Herdr wording corrected by ticket 08

Ticket 08 landed the container-side reporter and corrected the draft guide's
Herdr statements: the socket bullet now names the sandbox-owned reporter (not
Herdr's own Pi integration, which is neutralised inside the sandbox), the
"plain terminal" and "blocked prompts never appear" troubleshooting rows now
point at Herdr reachability and the mounted `permission-gate` extension, and a
limitations bullet records that Herdr 0.9.3 stores no session reference for a
custom source. The rest of the guide — the README move, first-run timing, and
the erlang/elixir convergence failure — is still this ticket's work and still
awaits ticket 04.