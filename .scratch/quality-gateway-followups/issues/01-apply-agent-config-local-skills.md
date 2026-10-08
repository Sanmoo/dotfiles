# 01: Apply the agents package on checkouts with local skill installs

**Origin:** `.scratch/quality-gateway/spec.md`, Out of Scope, item 1.

**What to build:** on the author's own machine, applying the `agents` package works while machine-local external skills are installed. Today the apply step aborts for every operation, so the package cannot be applied there at all.

**Blocked by:** None (can start immediately), but a design decision must be recorded before implementation. The options are: ignore untracked entries; derive the ignore set from the package's own `.gitignore`; or stage only tracked content. Choosing one needs its own specification.

**Status:** ready-for-agent

- [ ] Applying the `agents` package succeeds on a checkout that contains machine-local external skill installs.
- [ ] The design choice is recorded in a spec before implementation starts.
- [ ] Local skills are not published as part of the package.
- [ ] The final assertion of the external skills test still holds against the live checkout.

## Comments

Design recorded before implementation in
`.scratch/apply-agent-config-local-skills/spec.md`. The decision is to publish
only content tracked by the checkout: `apply-agent-config` asks Git for every
untracked path under `agents/` and passes each to Stow as an `--ignore`
pattern. The Git index is the single source of truth, so no machine-local list
has to be maintained and any untracked leftover — including empty directories —
is skipped whole.
