# Apply only tracked agent content

Status: implemented (the single authorized follow-up ticket, quality-gateway-followups/issues/01-apply-agent-config-local-skills.md, is resolved; covered by tests/external-skills-local-installation-test.sh)
Design: decided
Implementation authorization: granted for the single follow-up ticket
`quality-gateway-followups/issues/01-apply-agent-config-local-skills.md`

## Problem Statement

`general/bin/apply-agent-config` applies the `agents` package with GNU Stow:

```sh
stow --no-folding --simulate --dir="$checkout" --target="$home" agents
stow --no-folding --dir="$checkout" --target="$home" agents
```

On a checkout that carries machine-local external skill installs, the package
source tree contains gitignored absolute symlinks under
`agents/.agents/skills/`. Real Stow refuses to stow an absolute symlink
("source is an absolute symlink") and aborts every operation, so the package
cannot be applied at all on the author's own machine.

The repository already declares the separation this defect contradicts:
machine-local skill content is untracked, and only configuration and
user-authored skills are versioned. The apply step must therefore publish
exactly what the checkout tracks, and leave everything untracked alone.

## Decision

**Publish only content tracked by the checkout. Ask Git for every untracked
path under the package and tell Stow to ignore each one.**

`apply-agent-config` runs, from the checkout:

```sh
git ls-files --others --directory -z -- agents
git ls-files --others --ignored --exclude-standard --directory -z -- agents
```

The union is every untracked path under the package — files, symlinks, and
directories, including empty directories and gitignored entries. Each path is
made relative to the Stow target (the `agents/` prefix is dropped), anchored,
regex-escaped, and passed to both Stow invocations as `--ignore`. Stow then
descends the tracked tree only; an untracked directory is skipped whole, so
Stow never meets the absolute symlinks that made it abort.

The Git index is the single source of truth. There is no second list of
machine-local names to maintain and no drift between the list and the
filesystem: a newly installed skill is untracked, so it is ignored
automatically.

### Consequences accepted

- `apply-agent-config` now requires `CHECKOUT` to be a Git work tree that
  tracks content under `agents/`. It fails with a clear, non-zero result
  otherwise, rather than silently applying nothing.
- Content authored but not yet committed is not applied. The README tells the
  reader to commit an authored skill before applying it; `stow agents` run by
  hand remains available for pre-commit experimentation.
- The machine-local skills are neither published into `$HOME/.agents/skills`
  nor modified. Applying twice is unchanged.

### Options considered and rejected

1. **Ignore untracked entries** — chosen, as above.
2. **Derive the ignore set from `agents/.agents/.gitignore`.** This keeps Git
   out of the apply path, but it means implementing Git's ignore syntax (or a
   documented subset that hard-errors on the rest), and it only skips what the
   file happens to list. An install that is not added to `.gitignore` brings
   the abort back. It also duplicates the machine-local list that Git already
   knows. Pointing Stow at a package `.stow-local-ignore` instead would replace
   Stow's built-in ignore list and start publishing `.gitignore` into the home,
   which is worse.
3. **Stage only tracked content.** Stow links into its source tree, so a staged
   temporary tree yields home links that dangle as soon as the staging
   directory is removed, and a persistent shadow tree silently changes where
   every home link points. Rejected as a correctness hazard.

## Approved Behavioral Contract

1. `apply-agent-config CHECKOUT [HOME_DIRECTORY]` keeps its interface, its
   refusal of symlinked shared directories, and its simulate-then-apply order.
2. Applying succeeds on a checkout that contains machine-local external skill
   installs, including gitignored absolute symlinks under the package.
3. Only content tracked by `CHECKOUT` is published. An untracked entry is never
   linked into `HOME`, and an untracked directory is never created there.
4. Local skills already present in `HOME` are neither overwritten nor removed;
   reapplication stays a no-op for them.
5. A `CHECKOUT` that is not a Git work tree, or that tracks no content under
   `agents/`, is a clear non-zero error.
6. `tests/external-skills-local-installation-test.sh` exercises the defect: its
   apply fixture is a Git checkout that also carries a machine-local absolute
   symlink, and applying must succeed while that entry is absent from `HOME`.
   The test's final assertion still inspects the live checkout.

## Testing Decisions

- The existing shell test is the integration seam. It already runs the real
  script and real Stow against an isolated `HOME`, so the fix is proven by
  behavior, not by inspecting internals.
- The apply fixture is made a Git checkout (`git init`, `git add -A`, commit)
  and given an untracked absolute symlink named by the package `.gitignore`,
  reproducing the live checkout. The test asserts the apply succeeds and that
  the local skill is absent from the fresh home.
- The live-checkout assertion (only `jira-issue-formatting` is a real directory
  under `agents/.agents/skills/`) is unchanged.

## Out of Scope

- Migrating the author's real machine, or installing, updating, or selecting
  external skills.
- Applying from a non-Git checkout, or from a tarball export of the repository.
- Changing GNU Stow's handling of absolute symlinks.
