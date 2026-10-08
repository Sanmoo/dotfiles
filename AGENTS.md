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

## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles map 1:1 to label strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

single-context. See `docs/agents/domain.md`.
