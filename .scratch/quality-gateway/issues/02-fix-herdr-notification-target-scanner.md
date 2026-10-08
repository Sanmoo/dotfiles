# 02: Fix the herdr notification-target scanner

**Origin:** `.scratch/quality-gateway/spec.md`, §8.2.

**What to build:** the herdr notification-target test evaluates every key binding block. Today its block scanner treats a following binding header as a reset and never checks the block it ends, so the `prefix+o` binding is only checked when it happens to be last in the file. The configuration file is correct and stays unchanged; only the test's scanner is fixed.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Every `[[keys.command]]` block is evaluated at any section boundary, including when another binding follows it.
- [ ] `tests/herdr-notification-target-test.sh` passes on `main`.
- [ ] The test fails when the `prefix+o` binding is deliberately broken.
- [ ] The herdr configuration file is unchanged.
