# 11 — Erlang/Elixir in the declaration break a steady `safe-pi` start

**What to build:** A definitive fix for the declared `erlang`/`elixir` tools so that a steady `safe-pi` start is fast and silent even when they are declared. Today they fail to build inside the image, so every normal start re-attempts the failing build before failing open (~30 s), and `safe-pi --prepare` exits non-zero. This contradicts ticket 04's "later starts install nothing and add no noticeable delay".

**Blocked by:** 04 — Declared environment installed inside the container (the convergence this regresses)

**Status:** needs-info

- [ ] A steady `safe-pi` start (toolchain already converged) is silent and adds no multi-second delay while `erlang`/`elixir` are declared.
- [ ] A machine with the declared environment runs `safe-pi --prepare` and exits zero, or the failure is reported once with an explicit, actionable cause rather than re-attempted every start.

## What is known

- The global declaration (`mise/.config/mise/config.toml`) pins `erlang = "latest"` and `elixir = "latest"`. The sandbox converges this whole declaration on every start, so both are attempted for every sandbox, not only for repositories that need them.
- Ticket 05 observed the failure inside the image: `configure: error: No curses library functions found`, with `autoconf` and `libssl-dev` also missing. `safe-pi --prepare` exits non-zero, and every normal start retries the failing build (~30 s) before the fail-open warning.
- The image intentionally carries only base build tooling (`build-essential`, `pkg-config`, `python3`, …); erlang's source build needs more.
- mise's probe (`mise install --dry-run-code`) reports the tool as missing, so the install runs again on every start; a failed install is not remembered as "known bad".

## Open questions (why this is `needs-info`)

- Does the sandbox need `erlang`/`elixir` at all? Should they move out of the machine-wide declaration into the per-repository `.mise.toml` of projects that use them, so a steady sandbox never pays for them?
- If they stay declared: fix by building them (which extra image packages — `libncurses-dev`, `autoconf`, `libssl-dev`, …? and what does that cost in image size and rebuild time?), or by switching to a precompiled OTP (a different mise backend / a pinned binary release) instead of a source build?
- Should the probe treat a declared-but-known-unbuildable tool as converged and skip it with one warning, so the fail-open start is fast? That is a workaround for the symptom, not a fix for the declaration.
- Where does the timeout/delay really come from — the build attempt, the `latest` resolution, or both? A quick measurement would bound the fix.
- Does this reopen ticket 04's acceptance ("later starts install nothing and add no noticeable delay") or land as a separate fix that ticket 04 references?

## Acceptance criteria (draft, pending the answers)

- [ ] With the declaration unchanged (or with the agreed change), a steady start from a converged volume adds no noticeable delay and prints no convergence output.
- [ ] `safe-pi --prepare` on the declared environment exits zero, or the chosen alternative (per-repo pins, precompiled OTP) is why the tool is no longer converged in the sandbox.
- [ ] The guide's first-run/steady-start timing is corrected to the measured behaviour.

## Comments

### Reported (maintainer)

"Precisamos resolver definitivamente a questão da instalação do erlang via mise. Tem um impacto muito alto e chato na inicialização do safe-pi." Recorded from ticket 05's finding; raised against 04 at the time.
