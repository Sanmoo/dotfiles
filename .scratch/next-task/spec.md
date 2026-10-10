# next-task: report the next available task in this repository's tracker

Status: approved, implementation authorized (owner, 2026-10-09)
Design: settled in a grilling session on 2026-10-09

## Problem Statement

Deciding what to pick up next is done by hand today. The repository declares its
issue tracker in `docs/agents/issue-tracker.md` and its triage label strings in
`docs/agents/triage-labels.md`, and the local tracker's Wayfinding operations
section already defines a frontier ("open, unblocked, and unclaimed; first by
number wins") — but nothing reads those definitions back. The human scans
`.scratch/` or `gh issue list`, then separately remembers which tickets already
have a worktree or a branch, and which were claimed in the tracker.

Two things go wrong. Work that is already in progress gets picked up twice, and
work that the tracker declares ready is missed because it lives in a directory
nobody scanned. Both are answerable from state the repository already keeps; the
missing piece is a single read that consults it and says what is takeable.

## Solution

A skill, `/next-task`, that reports the next available task in the repository it
runs in, ranked in the tracker's own order, excluding the work already in
progress and naming the signals that did the excluding.

It is **read-only**. It never claims, labels, comments, or edits anything: the
claim belongs to `/implement`, made before implementation starts. The skill's
output is the text of the report, including the exact `/implement <ref>` line for
the recommended ticket.

## Decisions

1. **A skill, not a prompt template.** The procedure carries a recipe per tracker
   and per signal, which is `SKILL.md`-shaped, and the repository's authored
   procedure skills already live under `agents/.agents/skills/`. It is declared
   `disable-model-invocation: true`: an explicit `/next-task`, never the model
   deciding on its own to go looking for work.
2. **One home, two delivery paths.** The skill lives at
   `agents/.agents/skills/next-task/`. The `agents` Stow package delivers it to
   `~/.agents/skills/` on a machine that stows the package; the Skills CLI
   installs it anywhere else by path in this repository
   (`npx skills add Sanmoo/dotfiles -s next-task`, which the CLI's repo-wide
   discovery already resolves for the sibling skill `jira-issue-formatting`). It
   deliberately gets **no** `skills-lock.json` entry: that manifest exists for
   skill content that lives outside this repository, and this content ships with
   the package.
3. **The tracker doc is the contract.** The skill reads
   `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md` from the
   current repository and follows them; it never hard-codes a tracker, a label
   string, or a command the doc contradicts. With no tracker doc it stops and
   points at `/setup-matt-pocock-skills` — it does not fall back to `.scratch/`
   or guess a tracker.
4. **Scope is the current repository**, not the machine. Another repository's
   tracker is not consulted, and no checkout outside this one is read.
5. **Available means what the tracker declares**, in two kinds: build work
   (`ready-for-agent`, the string mapped by `triage-labels.md`) first, then the
   Wayfinder frontier when the tracker doc defines one. A ticket with no state
   recorded is not a candidate — the skill does not guess state.
6. **Claims exclude, git traces advise.** A tracker-native claim (assignee, a
   `claimed` state) is shared state and authoritatively removes the candidate. A
   local git trace — a worktree, a branch, or uncommitted changes naming the
   ticket — is a heuristic: it is reported as a warning, and the candidate is not
   silently dropped. `--include-busy` lists what either signal would exclude.
7. **Live agent sessions are out of scope.** Another Pi session, a Herdr pane, or
   a running subagent is not consulted. Implementation in this repository already
   requires a branch and a worktree, so a session actually working leaves a git
   trace; what remains is a session that only reads or plans, which does not
   conflict. The report states that this was not checked, so the exclusion is
   honest rather than implied.
8. **Order is the tracker's, and the recommendation is the first candidate.** The
   tracker doc's own rule when it defines one (the local frontier is "first by
   number wins"), otherwise number ascending; an explicit priority the tracker
   exposes comes first only when it exposes one. The agent does not re-rank by
   opinion.

## Out of Scope

- Claiming, or any other write to the tracker. `/implement` claims.
- Reading any repository other than the one the skill runs in.
- Live agent sessions, Herdr panes, and running subagents as work-in-progress
  signals (decision 7).
- Ordering or filtering by the agent's judgement of value.
- A `skills-lock.json` entry, and the `npx skills add` install on a machine that
  already stows the `agents` package (decision 2).

## Acceptance

1. `/next-task` in a repository whose tracker doc declares local markdown lists
   candidates from `.scratch/*/issues/*.md`: `Status: ready-for-agent` tickets as
   build work, and the frontier of any map as decisions, each in the tracker's
   order.
2. `/next-task` in a repository whose tracker doc declares GitHub lists the same
   two kinds through the commands that doc gives.
3. A repository with no `docs/agents/issue-tracker.md` stops with a message
   naming `/setup-matt-pocock-skills`, and lists nothing.
4. Nothing is written: no tracker file, label, comment, or assignee changes.
5. A candidate with a tracker-native claim is excluded and named under the
   set-aside section; a candidate with a git trace is listed with its warning;
   `--include-busy` lists both, each with the signal that would have excluded it.
6. The report names the recommended ticket with its `/implement <ref>` line, the
   remaining candidates in order, the set-aside entries with their signals, and
   one line stating that live agent sessions were not checked.
7. With no candidate at all, the report says so and stops.
8. `npx skills add Sanmoo/dotfiles -s next-task` resolves the skill by name, and
   `tests/external-skills-local-installation-test.sh` asserts that the `agents`
   package distributes exactly `jira-issue-formatting` and `next-task` under
   `agents/.agents/skills/`.
9. `tests/run --full` ends with `FULL GATE: PASS`.

## Comments

- 2026-10-09 (owner): the Full gate was red on two pre-existing `pi-deere` units, unrelated to this spec. The owner asked for them to be fixed in this task rather than deferred, so the branch also carries `pi-deere: stop the tests from racing a cold pi launch and a GNU stat` (b368dfc). It fixes `tests/pi-deere-test.sh`'s `stat` idiom, which breaks on GNU coreutils because `stat -f %Lp` prints the filesystem dump to stdout *and* exits 1, so the `||` fallback appended `700` instead of replacing it; and `tests/pi-deere-real-pi-test.sh`, whose fixture pointed `HOME` at a temporary directory, making the installed `pi` wrapper install a Node runtime and re-download its package on every launch, so the session started only after the tests' fixed windows had closed. `HOME` now stays the real one and the profile is isolated through `PI_CODING_AGENT_DIR`/`PI_DEERE_AGENT_DIR`; the two windows were widened past a cold launch. Full gate after the fix: `FULL GATE: PASS`, 26 of 26 units.
