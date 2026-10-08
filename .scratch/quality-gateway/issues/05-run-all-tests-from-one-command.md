# 05: Run every test file from one command

**Origin:** `.scratch/quality-gateway/spec.md`, §1, §4 and §5.

**What to build:** `tests/run` is the single entry point for the repository's tests. It discovers the three groups (shell tests, `general/bin` `.test` files, and the Bun suite under `pi/tests`), runs each one, and reports the result of each file with its duration and the total wall clock. It works from any directory. This ticket does not yet distinguish tiers; every file runs. Tier classification comes in ticket 06.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] `tests/run` discovers and runs all three groups.
- [x] Each file's name and duration are printed, followed by the total wall clock.
- [x] A failing test's captured output is shown; passing tests report only their duration.
- [x] No fail-fast: a red run reports every failure.
- [x] The runner exits 0 only when every test passed, and non-zero for a failed test or a runner error.
- [x] The runner works when invoked from a directory other than the repository root.

## Comments

Implemented by `tests/run` (commit 05), a tracked executable that resolves the repository root from its own location and works from any cwd. It discovers `tests/*-test.sh`, `general/bin/*.test`, and the Bun suite as a single unit, prints each file's name, tier and duration as it finishes, shows a failing file's captured output while passing files report only their duration, and ends with the summary and the total wall clock. There is no fail-fast: exit 0 (all passed) / 1 (at least one test failed) / 2 (runner error), with distinguishable messages.

Every unit runs with stdin closed and is bounded by `timeout 300`; the runner never sets or removes TMPDIR/TMP/TEMP, because the Bun tests create their scratch directories with `mkdtempSync(tmpdir(), ...)`.
