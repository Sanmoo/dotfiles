# 02: Reduce the startup cost of the http command

**Origin:** `.scratch/quality-gateway/spec.md`, Out of Scope, item 2.

**What to build:** each invocation of the `http` command starts faster. Today a bare `--help` costs about 74 ms, against about 10 ms for an empty interpreter. Across the roughly 114 invocations in the OC test suite, that is about 8.4 s of its 11 s. The plausible fix is to defer loading modules until they are needed.

**Blocked by:** None (can start immediately). Only worth doing if the Full gate budget is still at risk after the timeout fix (quality gateway ticket 4).

**Status:** resolved

- [x] The startup time of `http --help` is measured before and after on the reference machine, and recorded in the ticket.
- [x] The per-invocation startup overhead is substantially reduced. The spec projects the OC suite's 114 invocations going from about 8.4 s to about 4 s.
- [x] Existing tests of the `http` command pass without any change to their assertions.

## Comments

Implemented in `general/bin/http` and the new `general/bin/http_lib.py`.
The implementation moved into an importable module and the entry point became
a thin shim, so CPython caches the compiled bytecode in `__pycache__` and each
invocation stops recompiling the 1800-line source. Imports used by only some
paths (`base64`, `hashlib`, `json`, `shutil`, `subprocess`, `tempfile`, `time`,
`yaml`) moved into the functions that need them. The shim re-exports the
module namespace, so the tests that load `general/bin/http` directly through
`SourceFileLoader` are unchanged.

Reference-machine measurements (same checkout, `python3 3.14.6`, 71 runs):

| Metric | Before | After |
| --- | --- | --- |
| `http --help`, median | 73.8 ms | 41.8 ms |
| `http --help`, min | 70.0 ms | 40.4 ms |
| Overhead over bare interpreter, median | 64.1 ms | 32.2 ms |
| `tests/http-oc-test.sh`, wall | 11.19 s | 8.36 s |
| 110 OC invocations, sum | 8.43 s | 6.10 s |
| 110 OC invocations, median | 77 ms | 55 ms |

`http --help` is 43% faster and the per-invocation cost is down 29%. The OC
invocation sum landed at 6.1 s rather than the spec's 4 s projection: the
remaining cost is Python startup (≈10 ms), `argparse` plus the `_colorize`
machinery it now pulls in (≈16 ms), PyYAML (≈10 ms), and the other
hot-path imports, none of which deferral removes. Verified with
`tests/run --full`: `FULL GATE: PASS` (22 of 22 units), 9.99 s wall.
