# 11 — Erlang/Elixir in the declaration break a steady `safe-pi` start

**What to build:** A definitive fix for the declared `erlang`/`elixir` tools so a steady `safe-pi` start is fast and silent while they are declared. Pin the two tools in the tracked declaration to versions the host already has, and have the sandbox install Erlang/OTP from the precompiled Ubuntu 22.04 build that matches the image's base — refusing the source fallback — instead of compiling OTP from source. Convergence then succeeds in seconds, `safe-pi --prepare` exits zero, and a steady start installs nothing.

**Blocked by:** 04 — Declared environment installed inside the container

**Status:** resolved

- [x] With the declaration carrying the pins below, a converged machine's `safe-pi` start prints no convergence output and adds no noticeable delay (measured, recorded on this ticket).
- [x] `safe-pi --prepare` exits zero on the declared environment: the first converge installs the pinned erlang and elixir into the volume (~13 s measured), later runs install nothing.
- [x] The sandbox runs the pinned versions: inside `safe-pi --shell`, `erl` reports OTP 29 and `elixir --version` reports `1.20.2-otp-29`.
- [x] The sandbox never falls back to a source build: a pin with no precompiled build for the target fails fast, without the 107 MB source download, and `--prepare` reports it with a non-zero exit. (Recipe: temporarily target `ubuntu-20.04`, which Bob has no OTP 29 build for.)
- [x] The pin costs the host nothing: the next host `mise install` neither downloads nor compiles erlang/elixir, because the pins equal what is already installed.
- [x] The change stays sandbox-scoped and minimal: the tracked declaration gains only the two pins (no `[settings.erlang]`, the other tools keep `latest`), and host mise behaviour is unchanged.
- [x] An existing `safe-pi:current-u<uid>` image is rebuilt on next use, so the change reaches a machine that already has one.
- [x] The entrypoint harness asserts that mise runs with the precompiled target and the source-build refusal set, the way it already asserts the data/cache/state directories.
- [x] Ticket 06, which owns the guide, gains the measured first-run and steady-start numbers and the note that `erlang`/`elixir` are pinned exceptions to the declaration's `latest` story.

## What to change

- `mise/.config/mise/config.toml`: `erlang = "29.0.4"` and `elixir = "1.20.2-otp-29"` replace their `latest` entries. No other tool changes; no `[settings.erlang]` is added.
- `safe-pi/entrypoint.sh`: export `MISE_ERLANG_PRECOMPILED_OS="${MISE_ERLANG_PRECOMPILED_OS:-ubuntu-22.04}"` and `MISE_ERLANG_COMPILE="${MISE_ERLANG_COMPILE:-false}"` beside the existing mise variables, so convergence owns the sandbox's OTP provenance and a direct image run gets it too.
- `safe-pi/Dockerfile` and `pi/.local/bin/safe-pi`: bump the `safe-pi.entrypoint` label from `2` to `3`, and the wrapper's `image_has_entrypoint` comparison with it, so an existing `current` image is rebuilt on next use.
- `tests/safe-pi-entrypoint-test.sh`: assert that the two settings reach mise, the way `cache=`/`state=` already are.
- `docs/adr/0002-pi-in-docker-sandbox.md`: the decision and its alternatives are appended there.

## What is known

- The failure is the source build, not `latest` resolution. `safe-pi --prepare` failed twice, 52 s and 53 s: `erlang@29.1.1` downloaded `otp_src_29.1.1.tar.gz` (107 MB, ~25 s) and ran `configure` for ~26 s until `No curses library functions found`; `elixir@latest` was skipped as a failed dependency. The failed attempt leaves nothing behind (mise's erlang cache: 108 KB), so every start paid the full 107 MB again.
- mise's built-in erlang backend is binary-first: precompiled from Bob for Ubuntu 20.04/22.04/24.04, kerl source build elsewhere. The image reports Debian bookworm, so it compiled.
- With `MISE_ERLANG_PRECOMPILED_OS=ubuntu-22.04` inside the image, erlang 29.1.1 installed in 10 s (78.3 MB) and `erl` printed `otp 29`; elixir 1.20.4-otp-29 installed in 1.4 s; a declaration holding only those two converged in 13.2 s; the steady probe (`mise install --dry-run-code`) took 5 ms. No extra apt package was needed.
- Nothing in the home tree uses Erlang or Elixir, and the host has erlang 29.0.4 / elixir 1.20.2-otp-29 installed from the same declaration. The host is Arch (glibc 2.44), where the precompiled target would be a foreign binary and `compile = false` would break installs outright — so both settings stay sandbox-scoped.

## Comments

### Reported (maintainer)

"Precisamos resolver definitivamente a questão da instalação do erlang via mise. Tem um impacto muito alto e chato na inicialização do safe-pi." Recorded from ticket 05's finding; raised against 04 at the time.

### Grilling session (2026-10-09)

Measured against the real image and daemon; these numbers are what settled the open questions.

- `safe-pi --prepare` failed deterministically, 52 s then 53 s, on the 107 MB OTP source download plus a `configure` that cannot find curses. A failed install is not remembered, and mise's erlang cache holds 108 KB afterwards, so the full download repeated on every start.
- `latest` resolution is not the cost: mise answers the steady probe in 5 ms; the delay was entirely the build attempt.
- Precompiled OTP from Bob works on this image: `MISE_ERLANG_PRECOMPILED_OS=ubuntu-22.04` installed OTP in 10 s, `erl` ran and printed `otp 29`, elixir followed in 1.4 s, and the two-tool declaration converged in 13.2 s. Ubuntu 22.04's glibc 2.35 is older than bookworm's 2.36, and the image already carries `libssl.so.3` and `libncursesw.so.6`, so no package was added.
- No repository in the home tree declares or uses Erlang/Elixir (no `mix.exs`, `rebar.config`, or `.ex{,s}` file; the one per-repository mise file sets a PATH env only).

Decisions:

- **Pins over `latest`**, at the versions the host already has: `erlang = "29.0.4"`, `elixir = "1.20.2-otp-29"`. Bob publishes 29.0.4 for the chosen target, the host pays no reinstall, and the window in which a new OTP release has no precompiled build disappears. The cost is freshness: the two are now bumped by hand.
- **Precompiled target plus `MISE_ERLANG_COMPILE=false`**, both exported by the entrypoint and therefore sandbox-only. The guard turns a missing precompiled build into a fast, loud failure instead of the 107 MB source-build fallback.
- **The "known-bad tool" skip mechanism was considered and dropped**, not built: with the pins and the guard, an install that cannot succeed fails cheaply, and a start must not silently pretend a declared tool is converged.
- **Retiring the tools to per-repository `.mise.toml` was rejected**: nothing uses them today, but that removes them from the host's global toolkit as well and only postpones a working sandbox install that costs 11 seconds once.
- **The guide's timing correction belongs to ticket 06**, which has not shipped; the numbers above are recorded there instead.
- **Ticket 04 stays `resolved`** with its correction comment; this ticket owns the fix, and ADR 0002 records the decision and the alternatives.

### Implemented (2026-10-09)

Integrated as `fde912f`, on the planning commit `41f7ec7`. `FULL GATE: PASS`
(23 of 23 units) in the worktree that carried the change.

Verified against the real daemon and the rebuilt image (entrypoint label `3`):

- **Convergence.** `safe-pi --prepare` exits zero. A fresh volume converged the
two pinned tools in 13.4 s (`erlang@29.0.4` 12.2 s from Bob's Ubuntu 22.04
build, `elixir@1.20.2-otp-29` 1.2 s) with the other 18 tools already present —
17.6 s wall clock for the whole first run, which also included the stale
image's rebuild (about a second: the heavy layers stay in the build cache).
- **Steady start.** Convergence is silent and costs 0.35 s; a full
`safe-pi --version` through the container takes 2.8 s, all of it container
startup.
- **Inside the sandbox.** `erl` resolves to the mise shim and prints `otp 29`;
`elixir --version` reports `Elixir 1.20.2 (compiled with Erlang/OTP 29)`.
- **No source fallback.** Targeting `ubuntu-20.04`, which Bob has no OTP 29
build for, fails in 0.22 s with `precompiled erlang is not available: expected
exactly one Hex OTP build record for OTP-29.0.4, found 0` — no download,
nothing installed.
- **Host untouched.** The pins name what the host already has: its
`mise install --dry-run-code` reports `mise all tools are installed` and exits
zero.

Found while verifying, not a regression this introduced and not fixed here: the
sandbox's locale. The wrapper forwards the host's `LANG=en_US.UTF-8`, which
`node:26-bookworm-slim` does not generate, so the Erlang VM starts with native
name encoding latin1 — every `elixir` invocation warns that it may malfunction,
including the one mise runs while installing Elixir on the first converge.
Raised as ticket 12.
