# 10: Verify the gate budgets on the reference machine

**Origin:** `.scratch/quality-gateway/spec.md`, acceptance criteria 1, 3 and 5.

**What to build:** a final check of the whole gateway on the reference machine (8 cores, default worker count). The Fast gate and the Full gate both run green within their budgets, and the Full gate covers the full test inventory. Timings and the file counts are recorded in this ticket.

**Blocked by:** 04, 07, 09

**Status:** needs-triage

- [ ] The Fast gate completes within 5 seconds, green, on the reference machine.
- [ ] The Full gate completes within 12 seconds, green, on the reference machine.
- [ ] The Full gate's set of files equals the union of both tiers, and its size equals the test inventory counted at the time of the check.
- [ ] Measured timings and file counts are recorded in this ticket.
