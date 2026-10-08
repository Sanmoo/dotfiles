# 01: Restore the auth-code-token test to green

**Origin:** `.scratch/quality-gateway/spec.md`, §8.1.

**What to build:** the auth-code-token test passes again. Its in-process stub does not accept the keyword argument that the command now passes, so the test fails before reaching its assertions. The stub is updated to accept and ignore that argument.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `tests/auth-code-token-test.sh` passes on `main`.
- [ ] The stub accepts the TLS context keyword and ignores it.
- [ ] Existing assertions are unchanged: stdout carries only the access token, the `--json` shape, the `--force-login` and `--auth-param` query behaviour, and the reserved-parameter rejections.
