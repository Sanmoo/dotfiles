# 09: Document the gate and the completion obligation

**Origin:** `.scratch/quality-gateway/spec.md`, §6, §9 and acceptance criteria 11 and 12.

**What to build:** the repository's `AGENTS.md` states that a task is not finished until `tests/run --full` has passed, and names the command and the `FULL GATE: PASS` verdict line as the evidence. The README's test section documents the two commands as the primary instruction, and keeps the per-test examples that explain what each test covers. The global `general/AGENTS.md` is not changed, because it applies to repositories with no tier distinction.

**Blocked by:** 01, 02, 03, 06. The obligation is only meaningful once the Full gate can pass green.

**Status:** needs-triage

- [ ] The repository's `AGENTS.md` states the completion obligation, naming `tests/run --full` and the `FULL GATE: PASS` verdict line.
- [ ] `general/AGENTS.md` is unchanged.
- [ ] The README's test section documents `tests/run` and `tests/run --full` as the primary instruction.
- [ ] The README keeps the per-test examples and what each test covers.
- [ ] The completion protocol itself (commit, `--ff-only` integration, cleanup) is unchanged.
