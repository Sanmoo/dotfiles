# Quality gateway

The vocabulary this repository uses for what its test gateway runs and what that
costs. It exists because "test", "suite" and "gate" were each being used for
different things.

## Language

**Unit**:
One thing the gateway runs and reports — a shell test file, a bash test file, or the Bun suite as a whole.
_Avoid_: test file, job, suite

**Tier**:
A unit's declared cost class, `fast` or `slow`, stated by the unit itself on a `# tier: slow` marker line.
_Avoid_: priority, importance, category

**Fast gate**:
The phase a bare `tests/run` runs: every fast-tier unit.
_Avoid_: quick suite, unit tests

**Full gate**:
The phase `tests/run --full` runs: both tiers, ending with the `FULL GATE:` verdict line. It is the contract for finishing a task.
_Avoid_: all tests, full suite

**Budget**:
What a gate is declared to cost: a total for the gate and a ceiling for each unit.
_Avoid_: timeout, limit

**Per-unit ceiling**:
The longest a unit of a given tier may take before the gateway marks it `OVER BUDGET`, which is reported and not fatal.
_Avoid_: timeout, budget

**Critical path**:
The unit that decides a gate's wall clock, because units run in parallel and the total is bounded by the slowest one.
_Avoid_: bottleneck
