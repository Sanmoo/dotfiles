# 09: Document the gate and the completion obligation

**Origin:** `.scratch/quality-gateway/spec.md`, §6, §9 and acceptance criteria 11 and 12.

**What to build:** the repository's `AGENTS.md` states that a task is not finished until `tests/run --full` has passed, and names the command and the `FULL GATE: PASS` verdict line as the evidence. The README's test section documents the two commands as the primary instruction, and keeps the per-test examples that explain what each test covers. The global `general/AGENTS.md` is not changed, because it applies to repositories with no tier distinction.

**Blocked by:** 01, 02, 03, 06. The obligation is only meaningful once the Full gate can pass green.

**Status:** resolved

- [x] The repository's `AGENTS.md` states the completion obligation, naming `tests/run --full` and the `FULL GATE: PASS` verdict line.
- [x] `general/AGENTS.md` is unchanged.
- [x] The README's test section documents `tests/run` and `tests/run --full` as the primary instruction.
- [x] The README keeps the per-test examples and what each test covers.
- [x] The completion protocol itself (commit, `--ff-only` integration, cleanup) is unchanged.

## Comments

Implemented in `AGENTS.md` and `README.md` (commit 09). `AGENTS.md` gains a "Completion requires a green Full gate" section: a task is not finished until `tests/run --full` has passed, the evidence is the `FULL GATE: PASS` verdict line, a green Fast gate is necessary but never sufficient, and the existing completion protocol (commit, `git merge --ff-only`, remove the worktree and branch) is unchanged. `README.md` gains a "Run the tests" section documenting `tests/run` and `tests/run --full` as the primary instruction while keeping every pre-existing per-test example and its explanation.

`general/AGENTS.md` is unchanged (`git diff general/AGENTS.md` is empty).
