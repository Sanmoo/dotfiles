# Global agent defaults

These defaults apply across repositories. An applicable repository-specific
`AGENTS.md` takes precedence where it explicitly specifies a different workflow;
otherwise, follow the defaults below.

## Isolated development

- Before making development changes (including code, tests, configuration, or
  documentation), create a dedicated branch and Git worktree for the task.
- Place the worktree at `<repository-root>/.worktrees/<task-slug>/`, inside the
  repository's main checkout. When already in a linked worktree, locate the main
  checkout with `git worktree list`; keep worktrees as siblings, not nested.
- Ensure `.worktrees/` is ignored by the repository's root `.gitignore` before
  creating the worktree. If missing, add `/.worktrees/` as the only preparatory
  edit in the main checkout and include that change in the task branch as well.
  Verify with `git check-ignore .worktrees/<task-slug>/`.
- Perform all task edits, builds, and tests inside the isolated worktree. Preserve
  unrelated changes in the main checkout and other worktrees.
- When continuing the same task in its existing dedicated branch and worktree,
  reuse them. Read-only investigation does not require a new branch or worktree.
- Report the branch and worktree path when handing off the work. Leave them
  available for review; merge or remove them only when requested.
