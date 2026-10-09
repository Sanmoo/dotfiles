# 01: Apply the agents package on checkouts with local skill installs

**Origin:** `.scratch/quality-gateway/spec.md`, Out of Scope, item 1.

**What to build:** on the author's own machine, applying the `agents` package works while machine-local external skills are installed. Today the apply step aborts for every operation, so the package cannot be applied there at all.

**Blocked by:** None (can start immediately), but a design decision must be recorded before implementation. The options are: ignore untracked entries; derive the ignore set from the package's own `.gitignore`; or stage only tracked content. Choosing one needs its own specification.

**Status:** resolved

- [x] Applying the `agents` package succeeds on a checkout that contains machine-local external skill installs.
- [x] The design choice is recorded in a spec before implementation starts.
- [x] Local skills are not published as part of the package.
- [x] The final assertion of the external skills test still holds against the live checkout.

## Comments

Design recorded before implementation in
`.scratch/apply-agent-config-local-skills/spec.md`. The decision is to publish
only content tracked by the checkout: `apply-agent-config` asks Git for every
untracked path under `agents/` and passes each to Stow as an `--ignore`
pattern. The Git index is the single source of truth, so no machine-local list
has to be maintained and any untracked leftover — including empty directories —
is skipped whole.

Implemented in `general/bin/apply-agent-config` and
`tests/external-skills-local-installation-test.sh` (commits 3eeb02e, 608b7c3).
The apply step now runs `git ls-files --others --directory` and
`git ls-files --others --ignored --exclude-standard --directory` under
`agents/`, turns each untracked path into an anchored, escaped `--ignore`
pattern, and passes the set to both Stow invocations. A checkout that is not a
Git work tree, or that tracks no content under `agents/`, fails with a named
error instead of applying nothing. The README's apply section records the
consequences: the checkout must be a Git work tree, and an authored skill must
be committed before applying it.

The test fixture is now a Git checkout that carries a gitignored absolute
symlink under `agents/.agents/skills/` — the live defect reproduced hermetically
— and the test asserts the apply succeeds while that skill is absent from the
fresh home. The live-checkout assertion is unchanged. Both changes were reviewed
by the Standards and Spec reviewers; no blockers were found, and the two
Standards suggestions (name the escaping idiom, drop the duplicated Stow call)
were applied in 608b7c3. Verified with `tests/run --full`: `FULL GATE: PASS`
(22 of 22 units).
