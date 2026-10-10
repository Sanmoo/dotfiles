# 04: Report duration budgets and cut the real-pi unit

**Origin:** a grilling session with the maintainer on 2026-10-10, opened by a Full gate run that printed `FULL GATE: PASS` in 115.5s against the 12s budget recorded in `.scratch/quality-gateway/spec.md` (acceptance criterion 3, kept unmet in ticket 10).

**What to build:** the Full gate's wall clock is one unit, and had been for a while: `tests/pi-deere-real-pi-test.sh` launches the real `pi` 17 times around two fixed 15s windows, so no pool size, dispatch order or worker count can make the gate faster than that unit. Two things follow. The unit stops waiting on fixed delays and waits on the conditions it actually needs, keeping its clean shutdown. And the gateway declares what it costs and says so on every run, instead of leaving a number nobody reads to drift by 10x.

**Status:** resolved

- [x] Both fixed windows settle on a condition, keep the launch's clean shutdown, and are bounded by a ceiling that fails visibly. All 46 assertions are kept; none is added, removed or loosened.
- [x] The real-pi unit is split into units the gateway runs side by side, each with its own fixture and one shared harness.
- [x] The gateway declares a per-unit ceiling per tier and a total per gate, marks a unit `OVER BUDGET`, and does not change its exit status for a breach.
- [x] The Full gate is green on the reference machine within the declared budget, and the measurements are recorded below.
- [x] The decision is in `docs/adr/0006-duration-is-reported-not-enforced.md` and the vocabulary in `GLOSSARY.md`.

## Comments

Measured on the reference machine (8 cores, default worker count):

- **Before:** the unit alone 87.3s; the Full gate 89.4s, which was the unit's own duration to the hundredth of a second. Inside the unit, its two windows measured 16.0s and 17.8s of the 87.3s.
- **After the windows:** the unit alone 63.0 / 63.8 / 62.6s over three runs; the windows 4.2s and 5.6s; the Full gate 65.5s — still over the slow-tier ceiling, so the agreed trigger fired.
- **After the split:** Fast gate 21 units in 2.99s; Full gate 28 units in 36.57s, `FULL GATE: PASS`, and the summary line `duration budget (fast unit <=5s, slow unit <=60s, Full gate <=75s): WITHIN`.

The windows were not the whole cost: 17 real launches at ~3.1s each are ~53s, and only the split moves that off the critical path.

The 12s budget is superseded, not rewritten. `.scratch/quality-gateway/spec.md` is an archive of what was decided at the time and a later decision never rewrites it (see `docs/agents/issue-tracker.md`); ticket 10 keeps its unticked box as the record of the original budget.
