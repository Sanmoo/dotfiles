# 06: Classify slow-tier tests and add the Full gate verdict

**Origin:** `.scratch/quality-gateway/spec.md`, §2, §4 and §9.

**What to build:** a test declares itself slow-tier with a `# tier: slow` line in its header, next to the shebang. The bare invocation runs only the fast tier. `tests/run --full` runs both tiers and ends with the verdict line `FULL GATE: PASS` or `FULL GATE: FAIL`. Exactly two files carry the marker today: the OC test file and the `aws-console` test. Each file's tier appears in the per-file output.

**Blocked by:** 05

**Status:** resolved

- [ ] Exactly `tests/http-oc-test.sh` and `general/bin/aws-console.test` carry the marker.
- [x] The bare invocation excludes slow-tier files; `--full` includes them.
- [x] The set of files run by `--full` is a strict superset of the bare invocation's set.
- [x] Removing the marker from a file moves it into the fast tier.
- [x] A malformed or unrecognised marker makes the runner fail with a clear message, not a silent default.
- [x] The last line of a `--full` run is exactly `FULL GATE: PASS` or `FULL GATE: FAIL`; a failure exits non-zero and reports every failure.
- [x] Each file's tier is shown in the per-file output.

## Comments

Implemented by `tests/run` plus the marker lines (commit 06). A test declares its tier with a `# tier:` line in its file header (the leading run of blank/comment lines after the optional shebang). Values `slow` and `fast` are accepted; no marker means fast. A malformed value, an empty value, a keyword that contains "tier" but is not exactly `tier`, or two conflicting markers is a runner error naming file:line and exiting 2. Bare `tests/run` runs the fast tier; `--full` runs both tiers and prints the total wall clock followed by a last line of exactly `FULL GATE: PASS` or `FULL GATE: FAIL`; every unit's tier is shown in its output line.

Review follow-ups: commit 06 scoped marker detection to the header so a `# tier:` line in the file body is ignored rather than silently honoured, and added the keyword check; commit 06b classified the newly merged `tests/safe-pi-entrypoint-test.sh` (4.4s alone, 88% of the Fast budget) as slow-tier.

DEVIATION (criterion 4): four files carry `# tier: slow`, not the two the criterion enumerates — `tests/http-oc-test.sh`, `general/bin/aws-console.test`, `tests/http-oc-post-response-scripts-test.sh` (5.4s alone, above the 5s Fast budget), and `tests/safe-pi-entrypoint-test.sh` (4.4s alone; landed on `main` after this spec was written). Spec §2's classification rule — "a test that alone approaches or exceeds the Fast gate's wall budget belongs to the slow tier" — governs, and criterion 3's Fast half requires it. Criterion 4's enumeration predates those measurements; the box below is knowingly left unticked. The deviation is one line per file and trivially reversible.
