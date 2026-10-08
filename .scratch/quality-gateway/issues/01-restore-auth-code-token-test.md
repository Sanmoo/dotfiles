# 01: Restore the auth-code-token test to green

**Origin:** `.scratch/quality-gateway/spec.md`, §8.1.

**What to build:** the auth-code-token test passes again. Its in-process stub does not accept the keyword argument that the command now passes, so the test fails before reaching its assertions. The stub is updated to accept and ignore that argument.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] `tests/auth-code-token-test.sh` passes on `main`.
- [x] The stub accepts the TLS context keyword and ignores it.
- [x] Existing assertions are unchanged: stdout carries only the access token, the `--json` shape, the `--force-login` and `--auth-param` query behaviour, and the reserved-parameter rejections.

## Comments

Implemented in `tests/auth-code-token-test.sh` (commit 01). The in-process Python stub now reads `lambda url, data, ssl_context=None` and ignores the keyword argument that `general/bin/auth-code-token` passes; every existing assertion is unchanged (stdout carries only the access token, `--json` shape, `--force-login`/`--auth-param` query behaviour, reserved-parameter rejections).

Verified: `bash tests/auth-code-token-test.sh` passes; breaking the stub's return value makes it fail, so the pass is not vacuous.
