## Task management happens on `main`

This repo deliberately differs from the global default that puts every change in a
worktree. Task management commits land directly on `main`, with no branch and no
worktree:

- creating or editing a spec, a map, or a ticket
- moving a ticket's `Status:`, ticking its acceptance boxes, or appending to its
  `## Comments`
- ADRs and glossary terms that came out of planning

When `main` advances while an implementation branch is open (task-management
commits landing on `main` are the usual cause), rebase the implementation branch
onto `main` in its worktree, then integrate with `git merge --ff-only` from the
main checkout. That recovery is the default; no confirmation is needed.

A branch and worktree are created only when implementation starts, from `main`,
and carry only the implementation: code, tests, and the documentation that ships
with the behavior. `.scratch/**` is never edited inside a worktree. See
`docs/agents/issue-tracker.md` for the operational detail.

## Completion requires a green Full gate

The Quality gateway is this repository's automated validation, taken as a whole.
It runs in two phases. `tests/run` is the single entry point: it runs the
Fast gate, the tests cheap enough to re-run freely while working.
`tests/run --full` runs the Full gate — the Fast gate's files plus the slow tier
— and ends with the explicit verdict line `FULL GATE: PASS` (`FULL GATE: FAIL`
otherwise).

A task is not finished until `tests/run --full` has passed. The evidence is that
final verdict line: quote `FULL GATE: PASS` in the completion report. A green
Fast gate is necessary but never sufficient — a bare `tests/run` prints no
verdict, so a green Fast gate only means the next Full gate is worth running.

The Full gate is a precondition of the completion protocol (commit the task's
changes, integrate with `git merge --ff-only`, remove the worktree and branch),
not a replacement for it.

## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles map 1:1 to label strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

single-context. See `docs/agents/domain.md`.
