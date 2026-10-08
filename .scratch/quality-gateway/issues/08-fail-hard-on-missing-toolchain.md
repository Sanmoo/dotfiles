# 08: Fail hard when a test toolchain is missing

**Origin:** `.scratch/quality-gateway/spec.md`, §5.

**What to build:** when a group's interpreter or tool is unavailable (for example `bun`, which the Bun suite needs), the runner fails with a message naming the missing dependency and the test group it blocks. A missing toolchain is a broken environment, not a skipped group, so the run never reports it as skipped and never exits 0.

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] With `bun` unavailable, `tests/run` exits non-zero.
- [ ] Its message names `bun` and the `pi/tests` group it blocks.
- [ ] The group is not reported as skipped.
- [ ] A missing dependency produces a message distinguishable from a failed test.
