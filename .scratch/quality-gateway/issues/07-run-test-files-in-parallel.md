# 07: Run the test files in parallel

**Origin:** `.scratch/quality-gateway/spec.md`, §3.

**What to build:** the runner executes test files concurrently. The default worker count is the number of available CPUs, and the caller can override it. The Bun suite runs as one unit. Parallel execution must not serialise the suite to work around a test that is not isolated; such a test is fixed instead.

**Blocked by:** 05

**Status:** resolved

- [x] Test files run concurrently, with the default worker count equal to the available CPUs.
- [x] The caller can override the worker count.
- [x] The Bun suite runs as one unit.
- [x] No shared mutable state is introduced between test files.
- [x] A test that cannot run beside its peers is fixed, not run serially.

## Comments

Implemented by `tests/run` (commit 07): a bounded worker pool whose default is `nproc` (falling back to `getconf _NPROCESSORS_ONLN`, then 1) and is overridable with `--jobs N` or `--jobs=N`; a non-positive or non-numeric value is a runner error. Completions are read from a FIFO and reported as they happen, per-unit capture files are index-unique, the Bun suite stays one unit, and stdin/timeout/exit/verdict semantics from tickets 05-06 are preserved.

Isolation fix: `pi/tests/pi-agent/session-model-isolation.test.ts` now saves, removes, and restores `PI_SUBAGENT_CHILD` around the extension call. The extension deliberately no-ops when `PI_SUBAGENT_CHILD=1` (set in every Pi subagent session), which made 4 of the 30 Bun tests fail whenever the gate was run from inside a Pi subagent. This was the only coupling found; the extension itself is unchanged.

Review follow-up: commit 07a dispatches slow-tier units first in a Full gate (longest-processing-time-first), keeping the critical path off the end of the run.

A test that cannot run beside its peers was fixed, not serialised: repeated `--jobs 8` runs (and `--jobs 32`) showed no cross-test interference.
