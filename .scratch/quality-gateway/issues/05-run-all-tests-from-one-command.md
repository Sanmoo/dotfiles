# 05: Run every test file from one command

**Origin:** `.scratch/quality-gateway/spec.md`, §1, §4 and §5.

**What to build:** `tests/run` is the single entry point for the repository's tests. It discovers the three groups (shell tests, `general/bin` `.test` files, and the Bun suite under `pi/tests`), runs each one, and reports the result of each file with its duration and the total wall clock. It works from any directory. This ticket does not yet distinguish tiers; every file runs. Tier classification comes in ticket 06.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `tests/run` discovers and runs all three groups.
- [ ] Each file's name and duration are printed, followed by the total wall clock.
- [ ] A failing test's captured output is shown; passing tests report only their duration.
- [ ] No fail-fast: a red run reports every failure.
- [ ] The runner exits 0 only when every test passed, and non-zero for a failed test or a runner error.
- [ ] The runner works when invoked from a directory other than the repository root.
