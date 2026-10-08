# Quality gateway: a Fast gate and a Full gate

Status: implemented (tickets 01–10 resolved; measured budgets and two knowingly unmet
acceptance boxes are recorded in `issues/06` and `issues/10`)
Design: approved
Implementation authorization: granted for tickets 01–10 only (owner, 2026-10-08)

The contract below was settled in a grilling session on 2026-10-08, against
measurements taken on the main checkout that day. The user approved the design
and asked for the complete specification first, then approved its breakdown into
tickets under `issues/`. Implementation is authorized through those tickets only.
This document is not permission to delete or weaken any test, or to change the
validation obligation of any other repository.

## Problem Statement

The repository owns tests in three places:

- `tests/*-test.sh` — 18 shell tests (HTTP/`oc` CLI, OAuth helpers, Herdr, Nvim,
  `workq`, external skill installation);
- `general/bin/*.test` — 2 bash tests (`aws-console`, `ecs-logs`);
- `pi/tests` — 30 Bun tests in 3 files.

There is no runner. The current convention is a bare loop:

```sh
for t in tests/*-test.sh; do bash "$t"; done
```

That loop has three defects. It misses every test outside `tests/*-test.sh`: the two
`general/bin/*.test` files and the three Bun files. It reports nothing about
duration, so no one can tell whether it is slow without measuring by hand. And
it provides no fast path, so the only way to validate a change is to pay the
whole cost — which for this repository is dominated by two files that exist
precisely to be slow.

Measured on 2026-10-08 on the reference machine (8 cores, `main` at 27515a5),
sequential, stdin closed, 300s timeout per file:

| Test | rc | seconds | Notes |
| --- | --- | --- | --- |
| `tests/http-oc-post-response-scripts-test.sh` | 0 | 23.6 | Two deliberate timeout scenarios ≈22s of it |
| `tests/http-oc-test.sh` | 0 | 11.1 | 114 process invocations of `general/bin/http` |
| `general/bin/aws-console.test` | 0 | 4.3 | Real subprocess + local HTTP stub |
| `tests/http-test.sh` | 0 | 3.0 | 37 invocations |
| `tests/nvim-clipboard-test.sh` | 0 | 1.2 | |
| `tests/chave-nfe-test.sh` | 0 | 0.6 | |
| `tests/external-skills-local-installation-test.sh` | 1 | 0.9 | 0.9s and green in a clean checkout; red in this one |
| `tests/auth-code-token-test.sh` | 1 | 0.1 | |
| `tests/herdr-notification-target-test.sh` | 1 | 0.0 | |
| `general/bin/ecs-logs.test` | 0 | 0.0 | |
| `pi/tests` (`bun test`) | 0 | 0.1 | 30 pass |
| 10 remaining `tests/*-test.sh` | 0 | ≤0.3 each | |

Total sequential ≈ 45s. Later commits modified `tests/safe-pi-wrapper-test.sh`, so
ticket 10 re-measures at the current commit. Running everything with `xargs -P8` today measures 24.3s
of wall clock — no cross-test interference was observed, and the wall is bound
by the slowest file, not by the sum.

Two costs explain almost all of it:

1. **The deliberate timeout scenarios.** `tests/http-oc-post-response-scripts-test.sh`
   defines `timeout.yaml` (two scripts each busy-looping 6000ms) and
   `multiple-timeout.yaml` (one script busy-looping 11000ms). Both are cut by a
   hardcoded limit: `general/bin/http` calls
   `subprocess.run(..., timeout=11)` and the JavaScript runner has its own
   `const deadline = Date.now() + 10000`. The tests therefore *wait out* the
   limit twice, ~22s, to assert that the limit exists.
2. **Process startup.** `python general/bin/http --help` costs 74ms against 10ms
   for a bare `python -c pass` (`import yaml` is 9.3ms, `argparse` 5.5ms; the
   rest is compiling and executing a 2727-line module). At 114 invocations that
   is ≈8.4s of `http-oc-test.sh`'s 11.1s.

Separately, three tests are red on a machine that has external skills installed
locally — the normal state of the author's machine. Their causes are unrelated
to duration and are specified in §8.

## Solution

One runner, two phases, one classification rule.

```sh
tests/run          # Fast gate  — the phase run while working
tests/run --full   # Full gate  — the phase that must pass before a task is finished
```

The Full gate contains every test the Fast gate runs, plus the tests marked as
slow-tier. A test declares its own tier on a `# tier: slow` line near the top of
its file; the absence of that line means fast. Only two files carry the marker
today: `tests/http-oc-test.sh` and `general/bin/aws-console.test`.

Tiering is not a statement about importance. Every test that exists today keeps
running in the Full gate, with its assertions intact; the Fast gate exists so
that the cheap majority can be re-run continuously, not so that anything can be
skipped permanently.

Projected cost after this specification is implemented, same machine and pool
size: **Fast gate ≈3.0-3.5s** (bound by `http-test.sh`), **Full gate ≈11.5-12s**
(bound by `http-oc-test.sh`), against 45s sequential today.

The two phases become an obligation, not a convenience: §6 records that a task
is not finished until the Full gate passes, and that this obligation is stated
in this repository's `AGENTS.md`.

## Approved Behavioral Contract

### 1. One runner, two phases

- `tests/run` is the single entry point for the repository's test suite. It
  discovers all three groups: `tests/*-test.sh`, `general/bin/*.test`, and the
  Bun suite under `pi/tests`.
- `tests/run` runs the fast tier only. `tests/run --full` runs the union of both
  tiers, and must prove the union: the set of files executed by `--full` is a
  superset of the set executed by the bare invocation.
- No test is excluded from the Full gate, and no assertion is removed or
  loosened by this work. The suite's coverage is a non-goal to change.
- The runner is a tracked script inside the repository. It must work from any
  checkout of this repository, without depending on the caller's current
  directory.

### 2. Tier classification lives in the test file

- A test joins the slow tier by carrying a `# tier: slow` comment line in its
  header, next to its shebang. The runner reads that marker; it does not
  maintain a separate list of file names.
- A file without the marker is fast-tier. An unrecognized or malformed marker is
  a runner error, not a silent default.
- `tests/http-oc-test.sh` and `general/bin/aws-console.test` carry the marker.
  The classification rule is individual cost: a test that alone approaches or
  exceeds the Fast gate's wall budget belongs to the slow tier. `http-test.sh`
  at ~3.0s stays fast-tier deliberately, which is what keeps the Full gate
  meaningful as a gate rather than a formality.
- Test file paths stay where they are. `tests/http-oc-test.sh` keeps its name
  and location, so that path references to it stay valid.

### 3. Parallel execution

- The runner executes tests concurrently, with a worker count defaulting to the
  machine's available CPUs and overridable by the caller.
- Tests are already isolated by construction: each uses `mktemp -d`, a fixture
  `HOME`, and stubbed `curl`/`aws`/browser binaries. Parallel execution must not
  introduce shared mutable state, and the runner must not serialize the suite to
  work around a test that is not isolated — a test that cannot run beside its
  peers is a defect in that test.
- The Bun suite runs as one unit.

### 4. Output and exit status

- Every run prints, per test file, its name, its tier, and its duration, plus
  the run's total wall clock.
- The Full gate's last line is exactly one of `FULL GATE: PASS` or
  `FULL GATE: FAIL`. This line is the signal the completion obligation is
  written against; a caller must never have to infer the verdict from the exit
  status of the last test that happened to run.
- The runner exits 0 only when every test it ran passed, and non-zero both when
  a test failed and when the runner itself failed (missing dependency, bad
  marker, unreadable file). Those two cases print distinguishable messages: a
  failed test is a red suite, a broken environment is not.
- No fail-fast by default. A red suite must report every failure in one run.
- A failing test's captured output is shown; passing tests report their
  duration only.

### 5. Missing dependencies are hard errors

- If a group's interpreter or tool is unavailable (for example `bun` missing, so
  `pi/tests` cannot run), the runner fails with a clear message naming the
  missing dependency and the test group it blocks.
- It must not report the group as skipped, and it must not exit 0. The
  repository declares its toolchain through `mise`; an absent tool is a broken
  environment, not a valid state to validate against.
- Silently green suites are the failure mode this runner exists to eliminate.

### 6. The Full gate is mandatory

- This repository's `AGENTS.md` states that a task is not finished until
  `tests/run --full` has passed, and names the command and the `FULL GATE:`
  verdict line as the evidence.
- The obligation is recorded **only** in this repository's `AGENTS.md`. It must
  not be added to `general/AGENTS.md`, which is published by Stow as
  `~/AGENTS.md` and applies to repositories that have no tier distinction at
  all. A global instruction that assumes two phases would be wrong everywhere
  else.
- The existing completion protocol (commit the task's changes, integrate with
  `git merge --ff-only`, remove the worktree and branch) is unchanged; the Full
  gate is a precondition of it, not a replacement.
- `README.md` documents the two commands in its test section, replacing the
  single-file `bash tests/...` examples as the primary instruction while keeping
  the per-test examples that explain what each test covers.

### 7. Bounded script-execution timeout

The two deliberate timeout scenarios must not cost 22 seconds to assert a
bounded failure.

- `general/bin/http` reads the post-response script-execution limit from an
  environment variable, `HTTP_OC_SCRIPT_TIMEOUT_SECONDS`, defaulting to the
  current 10-second production limit when unset or empty.
- The limit is enforced end to end: the value is passed to
  `general/bin/http-post-response-runner.js` so its internal deadline matches,
  and the Python-side `subprocess.run` timeout is set to that limit plus one
  second as a backstop. Changing only the Python timeout is not sufficient,
  because the message the user sees is produced by the JavaScript deadline.
- The user-visible message and its 10-second wording are unchanged for the
  default configuration; the wording must not hardcode a number that the
  environment variable can contradict.
- `tests/http-oc-post-response-scripts-test.sh` sets the limit to 1 second for
  the `timeout` and `multiple-timeout` scenarios, keeps their existing
  assertions (nonzero status and the execution-limit message, with no partial
  shell exports), and does not restructure the busy-loop fixtures.
- Production behavior is preserved: with the variable unset, the limit is still
  10 seconds, and an acceptance criterion below pins that.

### 8. Green baseline: the three failing tests

The three red tests are fixed as part of this work, before the runner is judged
against its budget: an optimizer measured against a red baseline cannot prove it
preserved the signal.

1. **`tests/auth-code-token-test.sh`** — the test's in-process stub defines
   `module.post_form = lambda url, data: {...}`, while `general/bin/auth-code-token`
   now calls `post_form(..., ssl_context=...)` after the client-certificate
   work. The stub is updated to accept and ignore that keyword argument. All
   existing assertions are retained: stdout carrying only the access token, the
   `--json` response shape, the `--force-login` and `--auth-param` query
   behavior, and the reserved-parameter rejections.
2. **`tests/herdr-notification-target-test.sh`** — the `awk` block scanner is
   wrong. Its block-start rule matches `[[keys.command]]` and executes `next`,
   so a block terminated by *another* `[[keys.command]]` header is never
   evaluated; the `prefix+o` block is only checked when it happens to be the
   last block in the file, which stopped being true when a later binding was
   appended. The scanner is fixed so every block is evaluated at any section
   boundary. `herdr/.config/herdr/config.toml` is correct and must not be
   changed to satisfy the test: it has `open_notification_target = ""`, an
   in-app `delivery = "herdr"`, and a `prefix+o` command binding that runs
   `focus-next-actionable-agent.sh`.
3. **`tests/external-skills-local-installation-test.sh`** — the test applies the
   repository package from the live `$ROOT_DIR`, where machine-local external
   skills exist as gitignored absolute symlinks under `agents/.agents/skills/`.
   Real Stow refuses to stow a source tree containing absolute symlinks and
   aborts the whole operation, so the test fails on any machine with local skill
   installations. The test becomes hermetic: the apply steps run against a
   fixture checkout whose `agents/` package contains only repository-tracked
   content. The final assertion stays in place against `$ROOT_DIR` — only
   `jira-issue-formatting` remains a real directory under
   `agents/.agents/skills/`. The product defect behind the abort is deferred;
   see "Out of scope".

### 9. Non-goals

- No test is deleted, merged, or weakened; no assertion is dropped to buy speed.
- The Fast gate is not a replacement for the Full gate, and no workflow may
  treat a green Fast gate as completion.
- The tier boundary is not a stability judgment: a slow-tier test is not
  presumed flaky.
- No CI system is introduced. The gateway runs where it runs today: in the
  agent's or the user's shell.
- Startup cost of `general/bin/http` and the internal structure of
  `http-oc-test.sh` are not changed by this specification; both are deferred.

## Acceptance Criteria for Implementation

1. `tests/run` discovers and runs all three groups, exits 0 when everything
   passes, and reports a per-file duration table plus the total wall clock.
2. `tests/run --full` runs a strict superset of the bare invocation's files, and
   its last line is `FULL GATE: PASS` (or `FULL GATE: FAIL` with a nonzero exit
   and all failures reported).
3. On the reference machine with the default worker count, the Fast gate
   completes within 5 seconds, and the Full gate within 12 seconds, both green.
4. Exactly `tests/http-oc-test.sh` and `general/bin/aws-console.test` carry the
   `# tier: slow` marker; removing the marker from a file moves it into the Fast
   gate, and a malformed marker makes the runner fail with a clear message.
5. The Full gate's file set equals the union of the two tiers, and the total
   number of executed test files matches the repository's test inventory.
6. With `bun` unavailable, `tests/run` exits non-zero, names the missing
   dependency, and does not report the group as skipped.
7. With `HTTP_OC_SCRIPT_TIMEOUT_SECONDS` unset, a post-response script sequence
   exceeding 10 seconds still fails with the existing execution-limit message;
   with the variable set to 1, the same failure is reported in about a second.
8. The `timeout` and `multiple-timeout` scenarios assert the same nonzero exit
   and the same message as before, and still verify that no shell exports were
   applied.
9. `tests/auth-code-token-test.sh`, `tests/herdr-notification-target-test.sh`,
   and `tests/external-skills-local-installation-test.sh` pass, and the first two
   still fail when the behavior they assert is deliberately broken (the tests
   are fixed, not defused).
10. The external skills test passes both in a clean checkout and in this
    checkout, where machine-local skill symlinks exist.
11. This repository's `AGENTS.md` states the completion obligation and names the
    command and the verdict line; `general/AGENTS.md` is unchanged by this work.
12. `README.md` documents `tests/run` and `tests/run --full`, and still explains
    what the pre-existing per-test examples cover.

## Out of Scope

Three findings are deferred and tracked as tickets in
`.scratch/quality-gateway-followups/issues/`:

1. **`apply-agent-config` aborts on checkouts with local skill installs.** The
   script runs `stow --no-folding --simulate/real --dir="$checkout" --target="$home" agents`.
   Because machine-local external skills live inside the stow source tree as
   gitignored absolute symlinks, Stow reports "source is an absolute symlink"
   and aborts *all* operations. The result is that applying the package is
   impossible on the author's own machine, and the test in §8.3 was only the
   messenger. This is a product defect with a real design choice attached (ignore
   untracked entries, derive the ignore set from `agents/.agents/.gitignore`, or
   stage tracked content only) and needs its own specification.
2. **`general/bin/http` startup cost.** 74ms per invocation, of which ~64ms is
   above a bare interpreter (`import yaml` 9.3ms, `argparse` 5.5ms, plus
   compiling and executing a 2727-line module). Lazy imports are the plausible
   fix, and the payoff is bounded by the measurement: bringing ~114 invocations
   from ≈8.4s to ≈4s, which would move the Full gate from ≈12s toward ≈7s
   without touching a single test. Ticket, not part of this specification.
3. **Splitting `tests/http-oc-test.sh`.** The file is 2729 lines of linear
   scenarios sharing progressive fixtures, with 88 inline sections and 7 helper
   functions; sharding it into parallel files would put the Fast-gate bound
   under 3s, at the cost of a structural refactor of the test suite. Only worth
   doing if (2) proves insufficient.

No ADR accompanies this design: the decision is cheap to reverse, unsurprising
to a future reader, and does not close off alternatives, so it fails the
three-part test for recording an ADR. The vocabulary it introduces is recorded
in `CONTEXT.md`.
