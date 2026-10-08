# 04: Bound the post-response script timeout by environment variable

**Origin:** `.scratch/quality-gateway/spec.md`, §7.

**What to build:** the post-response script execution limit can be set by the environment variable `HTTP_OC_SCRIPT_TIMEOUT_SECONDS`. The limit is enforced end to end: the value reaches the JavaScript runner's internal deadline, and the Python-side timeout is that limit plus one second as a backstop. With the variable unset, production behaviour stays at 10 seconds. The timeout scenarios in the post-response test set it to 1 second, so the bounded failure is asserted in about a second instead of about 22.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] With the variable unset, a script sequence exceeding 10 seconds still fails with the existing execution-limit message.
- [ ] With the variable set to 1, the same failure is reported in about one second.
- [ ] The `timeout` and `multiple-timeout` scenarios assert the same nonzero exit and the same message as before, and still verify that no shell exports were applied.
- [ ] The user-visible message does not hardcode a number that the variable can contradict.
- [ ] The busy-loop fixtures are not restructured.
