# Skill dependencies are tracked as a per-machine manifest replayed by `skills-sync`

An earlier decision (`.scratch/external-skills-local-installation/spec.md`) kept all
external skill state machine-local: content, source links, and installation
lockfiles left the checkout. That left "which skills do I want" existing only as an
effect, scattered across `~/.agents/skills`, so a new machine had nothing to run —
and the machine-local lockfile the CLI writes in global mode is a version ledger,
not a restore manifest: copied into an empty home, `npx skills update -g` reports
"all global skills are up to date" and installs nothing. The decision is to track
the **project manifest** — `$HOME/skills-lock.json`, the file `add` and `update`
read and rewrite — as one Stow package per machine, in the same variant pattern the
repository already uses for `pi-linux` and `pi-mac`: `skills-personal/` for the
personal Linux laptop, with upstream sources, and `skills-corporate/` for the
corporate macOS laptop, with fork sources. Each package provides `~/skills-lock.json`,
so exactly one is stowed per machine and the two never coexist. The CLI rewrites the
manifest through the Stow symlink with a plain write, which leaves the link intact
and turns the tracked copy into a lockfile that is reviewed and committed;
`general/bin/skills-sync` replays it through the CLI in project scope from `$HOME`,
reapplies the frontmatter patches in `skills-patches/`, and offers `diff` between the
profiles. Skill content stays machine-local, the bootstrap still installs nothing,
and the machine-local global `.skill-lock.json` stays out of the checkout, which
keeps `tests/external-skills-local-installation-test.sh` asserting what it always did.

## Considered Options

- **Keep all dependency state machine-local**, as the earlier spec decided. Rejected because a new machine then has nothing to run: the declaration is the artifact that makes a machine reproducible, and it was exactly the artifact that stayed untracked.
- **A separate private repository for the manifest and the sync script.** Rejected: it splits one machine's configuration across two places, and the per-machine variant already has an established home here as Stow packages. One repository is also what was asked for.
- **One tracked manifest shared by both machines.** Rejected: the personal machine consumes the public upstream and the corporate one a fork, so a single file is wrong on at least one of them. The difference between the profiles is the point, not noise to be collapsed.
- **Track a hand-written source list and derive the manifest.** Rejected: two sources of truth for the same selection, and `computedHash` — which is what makes `update` detect change — is only produced by the CLI.
- **Publish the patches through the `agents` package at `~/.agents/skills-patches/`.** Rejected after measuring: a pre-existing Stow conflict leaves that package unapplied on the personal machine, so the `harness-eval` flag would silently disappear on the next sync. The patches are read from the checkout the script resolves instead, which needs no package, cannot go stale, and works inside a worktree.
- **Fork a third-party skill to carry a local tweak.** Rejected for frontmatter-only tweaks such as the `disable-model-invocation` line: a fork means maintaining an upstream for one line, while a patch file is one line reapplied on every install. Content adaptations still belong in the fork.

## Consequences

- Adding or updating a skill changes the tracked manifest through the Stow symlink. Review it with `git diff` and commit it like a lockfile; `skills-sync` deliberately does not commit.
- The profiles drift independently: a skill added on one machine is not added to the other. `skills-sync diff` reports skills missing from a sibling profile and diverging sources, and exits 1 when they differ.
- A global install (`npx skills add -g`) is invisible to this setup, because it is recorded in the machine-local `~/.agents/.skill-lock.json`. `skills-sync add` refuses `-g` rather than accepting a machine that cannot be reproduced.
- The corporate profile's origin is recorded in this repository, which is what makes it a profile rather than a local secret; the repository is private, and only the source reference is published, never the fork's content.
- Skill content and the global lock stay outside the checkout, so applying the dotfiles still installs, updates, and selects nothing.
- The corporate profile starts as an empty seed: running `sync` there before its sources are rewritten would install the public upstream, the opposite of the intent, whereas an empty manifest installs nothing.
- Patches are surfaced from the checkout rather than from `$HOME`, so they survive the CLI rewriting `SKILL.md` on every install, and a `skills-sync` copied outside the checkout cannot find them.
- `skills-sync` is published by the `general` package, so the profile packages and the script are applied by the same Stow lines that apply everything else.
- This supersedes the earlier spec in part, as recorded in its `## Comments`; the migration, preservation, and authorship guarantees of that spec remain in force.
