# Global agent defaults

These defaults apply across repositories. An applicable repository-specific
`AGENTS.md` takes precedence where it explicitly specifies a different workflow;
otherwise, follow the defaults below.

## Isolated development

- Before making development changes (including code, tests, configuration, or
  documentation), record the current branch and checkout path as the integration
  destination, then create a dedicated branch and Git worktree for the task.
  If HEAD is detached, ask for the destination branch before starting.
- Place the worktree at `<repository-root>/.worktrees/<task-slug>/`, inside the
  repository's main checkout. When already in a linked worktree, locate the main
  checkout with `git worktree list`; keep worktrees as siblings, not nested.
- Ensure `.worktrees/` is ignored by the repository's root `.gitignore` before
  creating the worktree. If missing, add `/.worktrees/` as the only preparatory
  edit in the main checkout and include that change in the task branch as well.
  Verify with `git check-ignore .worktrees/<task-slug>/`.
- Perform all task edits, builds, and tests inside the isolated worktree. Preserve
  unrelated changes in the main checkout and other worktrees.
- When continuing the same task, reuse its dedicated branch and worktree and
  retain the originally recorded integration destination; ask if it is unknown.
  Read-only investigation does not require a new branch or worktree.

## Completion and cleanup

Unless the user or an applicable repository-specific `AGENTS.md` says otherwise,
complete the following without waiting for a separate integration request:

1. Validate the completed work and commit only the task's changes in its branch.
   If work is incomplete or validation fails, keep the branch and worktree and
   report the blocker instead of integrating.
2. Return to the recorded checkout, verify that the original branch is checked
   out, and run `git merge --ff-only <task-branch>` there. The destination is the
   branch the task started from, not necessarily `main`. Preserve unrelated local
   changes; if they block integration, stop and report the blocker.
3. Confirm that the task branch's tip is an ancestor of the destination branch
   and that the task worktree has no uncommitted or untracked work. From outside
   that worktree, remove it with `git worktree remove <task-worktree>`, then delete
   its branch with `git branch -d <task-branch>`. Remove only the branch and
   worktree created for this task, leaving pre-existing resources intact.
4. Report the destination branch, integrated commit, validation results, and
   cleanup status. If anything remains, include its branch and worktree path.

If fast-forward integration or safe cleanup is not possible, preserve the
remaining resources and ask how to proceed. Do not substitute a merge commit,
rebase, reset, or forced deletion. Integration is local; push only when requested.
