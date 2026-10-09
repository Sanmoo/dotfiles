# 10 — Resume the exact sandboxed session, not just the last one in the directory

**What to build:** The reporter's self-reported resume command must reopen the *same* conversation after a Herdr restart. `safe-pi -c` (continue the most recent session in the cwd) is not enough: with more than one session in the same directory it can reopen a different conversation. The command should name the session (for example `safe-pi --session <id>`).

**Blocked by:** 13 — Wire the self-reported resume command into the sandbox reporter (the mechanism 10 refines)

**Status:** needs-info

- [ ] With two sessions in the same directory, a Herdr restart reopens the one that was running, not just the newest.
- [ ] The resume command still satisfies Herdr's `resume_argv` rules (plain first command name, `safe-pi`; at most 64 args / 8 KiB; no apostrophes or control characters).

## What is known

- Pi accepts `--session <path|id>` (session file or partial UUID); `-c`/`--continue` picks the most recent session for the directory.
- The reporter knows `ctx.sessionManager.getSessionId()` and the container-only session file (`/run/safe-pi/sessions/<encoded-cwd>/<uuid>.jsonl`). The same session on the host lives at `~/.pi/agent/sessions/<encoded-cwd>/<uuid>.jsonl`.
- The resume command runs on the host in the pane's saved directory through `safe-pi`, which re-enters the sandbox and forwards `--session` to Pi inside it.

## Open questions (why this is `needs-info`)

- Is Pi's session id (the UUID) stable and resolvable with `--session <id>` both from the host and inside the sandbox, or must the resume command use a path?
- If it must be a path: should it be the host path (needs a container→host mapping) or the container-only path (invalid on the host)? Which layer derives it?
- Does the id stay valid across a Pi session fork/branch, and does the command need the model or other flags for parity?
- Does the reporter need to re-report the resume command whenever the session changes (`session_start`, `agent_start`)?

## Acceptance criteria (draft, pending the answers)

- [ ] A restored sandboxed pane reopens exactly the session that ran before the restart, proven with two sessions in the same directory.
- [ ] The command works when the pane's saved cwd is the directory that started the session.

## Comments

### Reported (maintainer)

`safe-pi -c` is not sufficient for auto-resume: it can open another session in
the same directory. Include a session id.

### Answers from the ticket 07 spike

Ticket 07 resolved the mechanism and settled the shape questions this ticket was
blocked on:

- The resume command runs **on the host**, typed into the restored pane's shell
  in the pane's saved cwd. A container-only session path
  (`/run/safe-pi/sessions/…`) does not exist there, so the argument must be
  something the host `safe-pi` can resolve. The session id (UUID), forwarded as
  `safe-pi --session <id>`, is the right form; the reporter knows it from
  `ctx.sessionManager.getSessionId()`.
- The command is typed, not `exec`'d, so `safe-pi` must stay a bare first token
  on the host shell's `PATH`; no path or quoting change is possible.
- Herdr keeps one resume slot per pane and replaces it on a newer report, so the
  reporter should re-report whenever the session changes (`session_start`,
  `agent_start`) rather than only once.
- Remaining open questions here are about Pi, not Herdr: whether a partial UUID
  resolves stably with `--session`, and whether it survives a fork/branch. The
  wiring itself is ticket 13; this ticket picks the exact argument once the
  mechanism is in place.
