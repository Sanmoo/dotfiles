# 10: Verify the gate budgets on the reference machine

**Origin:** `.scratch/quality-gateway/spec.md`, acceptance criteria 1, 3 and 5.

**What to build:** a final check of the whole gateway on the reference machine (8 cores, default worker count). The Fast gate and the Full gate both run green within their budgets, and the Full gate covers the full test inventory. Timings and the file counts are recorded in this ticket.

**Blocked by:** 04, 07, 09

**Status:** resolved

- [x] The Fast gate completes within 5 seconds, green, on the reference machine.
- [ ] The Full gate completes within 12 seconds, green, on the reference machine.
- [x] The Full gate's set of files equals the union of both tiers, and its size equals the test inventory counted at the time of the check.
- [x] Measured timings and file counts are recorded in this ticket.

## Comments

Verified on the reference machine (8 cores, default worker count 8) after integrating everything on `main`.

- Fast gate: **3.51s** wall, green, 18 units, within the 5s budget. Bound by `tests/http-test.sh` (3.18s) — exactly the bound the spec projected.
- Full gate: **12.64s** wall, green, 22 units, last line `FULL GATE: PASS` — 5.3% over the 12s budget. Bound by `tests/http-oc-test.sh`, which measures 10.7s alone but ~12.6s while running beside seven peers. The spec's own baseline method (`xargs -P8` over the full inventory) measures 12.52s on the same machine, so the overrun is parallel-execution contention on this machine, not runner overhead; longest-first dispatch (commit 07a) already beats that baseline.
- Inventory at the time of the check: 19 `tests/*-test.sh` (including `tests/safe-pi-entrypoint-test.sh`, which landed on `main` after the spec was written), 2 `general/bin/*.test`, and the Bun suite as one unit = 22 executed units. The Full gate's set equals the union of the two tiers (18 fast + 4 slow).
- Four files carry `# tier: slow`; see ticket 06 for the justified deviation from acceptance criterion 4.

Because the Full gate is over budget, the corresponding box below is knowingly left unticked. Machine variance matters: back-to-back repetitions degrade under memory/swap pressure, so these are spaced measurements on an otherwise idle machine.

Superseded on 2026-10-10: the 12s Full gate budget this ticket verifies was
replaced by a declared 75s total plus a 60s slow-tier ceiling, with a breach
reported as `OVER BUDGET` and never fatal. The unticked box above stays as the
record of the original budget. See
`docs/adr/0006-duration-is-reported-not-enforced.md` and
`.scratch/quality-gateway-followups/issues/04-duration-budgets-and-real-pi-window.md`,
where the re-measurement is recorded (Full gate 28 units in 36.57s, green).
