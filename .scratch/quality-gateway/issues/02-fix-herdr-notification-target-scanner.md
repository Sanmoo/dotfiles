# 02: Fix the herdr notification-target scanner

**Origin:** `.scratch/quality-gateway/spec.md`, §8.2.

**What to build:** the herdr notification-target test evaluates every key binding block. Today its block scanner treats a following binding header as a reset and never checks the block it ends, so the `prefix+o` binding is only checked when it happens to be last in the file. The configuration file is correct and stays unchanged; only the test's scanner is fixed.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Every `[[keys.command]]` block is evaluated at any section boundary, including when another binding follows it.
- [x] `tests/herdr-notification-target-test.sh` passes on `main`.
- [x] The test fails when the `prefix+o` binding is deliberately broken.
- [x] The herdr configuration file is unchanged.

## Comments

Implemented in `tests/herdr-notification-target-test.sh` (commit 02). The scanner now evaluates the current `[[keys.command]]` block at any section boundary and at EOF, instead of only when the block happens to be last. `herdr/.config/herdr/config.toml` is byte-for-byte unchanged.

Review follow-up (commit 02, rebased): the duplicated scanner was replaced by one `block_contains <pattern> <config>` function serving both checks. The pattern is passed through the environment rather than `awk -v`, because `awk -v` consumes the `\+` escape in `key = "prefix\+o"` and the literal `prefix+o` then fails to match. Pass/fail messages and exit behaviour are unchanged.

Falsified: changing the `prefix+o` key or its command in a copy of the config makes the test fail.
