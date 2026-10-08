# 06: Classify slow-tier tests and add the Full gate verdict

**Origin:** `.scratch/quality-gateway/spec.md`, §2, §4 and §9.

**What to build:** a test declares itself slow-tier with a `# tier: slow` line in its header, next to the shebang. The bare invocation runs only the fast tier. `tests/run --full` runs both tiers and ends with the verdict line `FULL GATE: PASS` or `FULL GATE: FAIL`. Exactly two files carry the marker today: the OC test file and the `aws-console` test. Each file's tier appears in the per-file output.

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] Exactly `tests/http-oc-test.sh` and `general/bin/aws-console.test` carry the marker.
- [ ] The bare invocation excludes slow-tier files; `--full` includes them.
- [ ] The set of files run by `--full` is a strict superset of the bare invocation's set.
- [ ] Removing the marker from a file moves it into the fast tier.
- [ ] A malformed or unrecognised marker makes the runner fail with a clear message, not a silent default.
- [ ] The last line of a `--full` run is exactly `FULL GATE: PASS` or `FULL GATE: FAIL`; a failure exits non-zero and reports every failure.
- [ ] Each file's tier is shown in the per-file output.
