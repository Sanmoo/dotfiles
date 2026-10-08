# 02: Reduce the startup cost of the http command

**Origin:** `.scratch/quality-gateway/spec.md`, Out of Scope, item 2.

**What to build:** each invocation of the `http` command starts faster. Today a bare `--help` costs about 74 ms, against about 10 ms for an empty interpreter. Across the roughly 114 invocations in the OC test suite, that is about 8.4 s of its 11 s. The plausible fix is to defer loading modules until they are needed.

**Blocked by:** None (can start immediately). Only worth doing if the Full gate budget is still at risk after the timeout fix (quality gateway ticket 4).

**Status:** needs-triage

- [ ] The startup time of `http --help` is measured before and after on the reference machine, and recorded in the ticket.
- [ ] The per-invocation startup overhead is substantially reduced. The spec projects the OC suite's 114 invocations going from about 8.4 s to about 4 s.
- [ ] Existing tests of the `http` command pass without any change to their assertions.
