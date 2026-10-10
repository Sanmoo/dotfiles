# The quality gateway reports duration and does not enforce it

The Full gate is the contract for finishing a task here, and by design it contains integrations that launch the real `pi` offline: those pay tens of seconds of process startup each, so the gate's wall clock is decided by its slowest unit and cannot reach a single-digit-second total without weakening or deleting a test the repository wants to keep. The gateway therefore declares what the gate costs — a per-unit ceiling per tier (fast 5s, slow 60s) and a total per gate (Fast 5s, Full 75s) — prints that verdict on every run, and marks a unit `OVER BUDGET` when it exceeds its ceiling; a breach never changes the exit status, because a red suite has to mean a broken assertion and not a slow machine. This ADR supersedes acceptance criterion 3 of `.scratch/quality-gateway/spec.md` (Full gate within 12s); that spec stays as the archive of what was decided then.

## Considered Options

- **Enforce the budget: a breach fails the run.** Rejected for now. Machine and toolchain variance moves these units by tens of percent — the same integration measured 87.3s alone and 115.5s inside a pool across two runs on the same machine — so a gate that turns that variance into red loses the signal it exists to carry. Promoting the ceiling to a failure needs a measurement history first.
- **A third tier for slow integrations** (`deep`), run on demand rather than per task. Rejected: the Full gate is the point, and moving a real integration out of it trades the obligation away for latency the declared budget already covers.
- **Keep only per-unit ceilings, drop the totals.** Rejected: the totals are the number a person reads to know what the gate costs.
