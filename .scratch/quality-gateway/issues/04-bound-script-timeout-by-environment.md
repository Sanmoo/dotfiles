# 04: Bound the post-response script timeout by environment variable

**Origin:** `.scratch/quality-gateway/spec.md`, §7.

**What to build:** the post-response script execution limit can be set by the environment variable `HTTP_OC_SCRIPT_TIMEOUT_SECONDS`. The limit is enforced end to end: the value reaches the JavaScript runner's internal deadline, and the Python-side timeout is that limit plus one second as a backstop. With the variable unset, production behaviour stays at 10 seconds. The timeout scenarios in the post-response test set it to 1 second, so the bounded failure is asserted in about a second instead of about 22.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] With the variable unset, a script sequence exceeding 10 seconds still fails with the existing execution-limit message.
- [x] With the variable set to 1, the same failure is reported in about one second.
- [x] The `timeout` and `multiple-timeout` scenarios assert the same nonzero exit and the same message as before, and still verify that no shell exports were applied.
- [x] The user-visible message does not hardcode a number that the variable can contradict.
- [x] The busy-loop fixtures are not restructured.

## Comments

Implemented in `general/bin/http`, `general/bin/http-post-response-runner.js`, and `tests/http-oc-post-response-scripts-test.sh` (commit 04). `HTTP_OC_SCRIPT_TIMEOUT_SECONDS` (unset or empty means 10) is resolved once, passed to the runner as `timeoutSeconds` so its internal deadline matches, and used for the Python `subprocess.run` backstop as limit + 1. The user-visible message is interpolated from the resolved limit, so its wording cannot contradict the variable, and the default wording is unchanged. The `timeout` and `multiple-timeout` scenarios set the limit to 1s; their assertions and busy-loop fixtures are unchanged.

Review follow-up (commit 04, rebased): a fast in-process assertion pins the default (unset -> 10, empty -> 10, a set value -> that value), satisfying the "pins that" clause without adding a 10-second wait to any gate. Falsified by changing the default to 5.

Default-10 behaviour was also verified end to end by the implementer: an 11s busy-loop sequence with the variable unset exits 1 after ~10s with the existing execution-limit message.
