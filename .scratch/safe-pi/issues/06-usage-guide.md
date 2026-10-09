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
limitations bullet records the session-reference situation. That bullet was
corrected after research: Herdr stores `agent_session` only for official
`herdr:*` sources (by design), while a custom source's self-reported
`resume_argv` has been accepted since 0.9.2, so automatic restore is a wiring
follow-up (ticket 07), not a missing release. The rest of the guide — the README
move, first-run timing, and the erlang/elixir convergence failure — is still
this ticket's work and still awaits ticket 04.

### Timing and the pinned exceptions (from ticket 11)

Ticket 11 is integrated as `fde912f`, and its measurements are the numbers this
guide should carry:

- **First run.** The image build (about a minute when cold) plus the toolchain
  convergence, which for a fresh volume is 13.4 s inside mise and 17.6 s wall
  clock for the whole run. The draft's "several minutes" is stale.
- **Steady start.** Convergence installs nothing, prints nothing and costs
  0.35 s; a full container start (`safe-pi --version`) takes 2.8 s, all of it
  container startup. The draft's "about a second" should be this number.
- `safe-pi --prepare` exits zero on the declared environment, first run and
  after.

One correction the draft does not have: `erlang` and `elixir` are the
declaration's two pinned exceptions (`29.0.4`, `1.20.2-otp-29`) while every
other tool stays `latest`. The sandbox installs them from Bob's precompiled
Ubuntu 22.04 build and refuses a source build, so a converged start never
compiles OTP. The "`latest` pins follow new releases the way they do on the
host" bullet still holds for the rest of the declaration.