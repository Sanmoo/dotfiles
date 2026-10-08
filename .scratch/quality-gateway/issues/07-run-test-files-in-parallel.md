# 07: Run the test files in parallel

**Origin:** `.scratch/quality-gateway/spec.md`, §3.

**What to build:** the runner executes test files concurrently. The default worker count is the number of available CPUs, and the caller can override it. The Bun suite runs as one unit. Parallel execution must not serialise the suite to work around a test that is not isolated; such a test is fixed instead.

**Blocked by:** 05

**Status:** needs-triage

- [ ] Test files run concurrently, with the default worker count equal to the available CPUs.
- [ ] The caller can override the worker count.
- [ ] The Bun suite runs as one unit.
- [ ] No shared mutable state is introduced between test files.
- [ ] A test that cannot run beside its peers is fixed, not run serially.
