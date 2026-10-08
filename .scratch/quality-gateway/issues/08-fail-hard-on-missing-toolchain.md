# 08: Fail hard when a test toolchain is missing

**Origin:** `.scratch/quality-gateway/spec.md`, §5.

**What to build:** when a group's interpreter or tool is unavailable (for example `bun`, which the Bun suite needs), the runner fails with a message naming the missing dependency and the test group it blocks. A missing toolchain is a broken environment, not a skipped group, so the run never reports it as skipped and never exits 0.

**Blocked by:** 05

**Status:** resolved

- [x] With `bun` unavailable, `tests/run` exits non-zero.
- [x] Its message names `bun` and the `pi/tests` group it blocks.
- [x] The group is not reported as skipped.
- [x] A missing dependency produces a message distinguishable from a failed test.

## Comments

No code change was required: ticket 05's `tests/run` already implements this behaviour, and the review confirmed it.

Independently verified on `main`: with `PATH=/usr/bin:/bin` (so `bun` is unavailable) `tests/run` exits 2 with `tests/run: RUNNER ERROR: the 'bun' tool is required to run the pi/tests group and was not found on PATH`. The message names `bun` and the `pi/tests` group it blocks, nothing is reported as skipped (`grep -in skip tests/run` is empty), and the runner-error path (exit 2, `RUNNER ERROR:` prefix) is distinguishable from a failed test (exit 1, red suite). A missing `timeout` is likewise a hard runner error.
