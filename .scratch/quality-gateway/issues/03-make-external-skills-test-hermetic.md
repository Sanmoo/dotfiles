# 03: Make the external skills installation test hermetic

**Origin:** `.scratch/quality-gateway/spec.md`, §8.3 and out-of-scope item 1.

**What to build:** the external skills installation test passes on any machine. Today it applies the live `agents` package, which contains machine-local skill symlinks, and Stow aborts on those. The apply steps run against a fixture checkout that contains only tracked content. The product defect itself is deferred to its own follow-up.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] The apply steps run against a fixture whose `agents` package contains only repository-tracked content.
- [x] The final assertion still checks the live checkout: only `jira-issue-formatting` is a real directory under the skills folder.
- [x] The test passes in a clean checkout and in this checkout, where machine-local skill symlinks exist.

## Comments

Implemented in `tests/external-skills-local-installation-test.sh` (commit 03). The apply steps now run against a fixture checkout built with `git -C "$ROOT_DIR" archive HEAD agents`, so real Stow never sees the machine-local absolute symlinks under `agents/.agents/skills/`. The `agents/.agents/skills` final assertion still reads `$ROOT_DIR`.

Final verification found a second live-checkout assertion of the same class: the "OpenCode must not distribute third-party skills" loop tripped over a machine-local leftover empty `opencode/.config/opencode/skills/docx/scripts/` directory in the main checkout. Git cannot track empty directories, so it is invisible to `git status` but visible to `[[ -e ]]`. Commit 03a archives `opencode` into the same fixture and evaluates that loop against the fixture; the loop still catches a genuinely distributed skill (falsified by committing `docx/SKILL.md` into the package).

Verified green in a clean worktree, in a worktree with the two machine-local absolute symlinks recreated, and in the main checkout with those symlinks present.
