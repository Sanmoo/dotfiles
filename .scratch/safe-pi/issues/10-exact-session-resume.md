# 10 — Resume the exact sandboxed session, not just the last one in the directory

**What to build:** The reporter's self-reported resume command must reopen the *same* conversation after a Herdr restart. `safe-pi -c` (continue the most recent session in the cwd) is not enough: with more than one session in the same directory it can reopen a different conversation. The command should name the session (for example `safe-pi --session <id>`).

**Blocked by:** 13 — Wire the self-reported resume command into the sandbox reporter (the mechanism 10 refines)

**Status:** ready-for-agent

- [ ] With two sessions in the same directory, a Herdr restart reopens the one that was running, not just the newest.
- [ ] The resume command still satisfies Herdr's `resume_argv` rules (plain first command name, `safe-pi`; at most 64 args / 8 KiB; no apostrophes or control characters).

## What is known

- Pi accepts `--session <path|id>` (session file or partial UUID); `-c`/`--continue` picks the most recent session for the directory.
- The reporter knows `ctx.sessionManager.getSessionId()` and the container-only session file (`/run/safe-pi/sessions/<encoded-cwd>/<uuid>.jsonl`). The same session on the host lives at `~/.pi/agent/sessions/<encoded-cwd>/<uuid>.jsonl`.
- The resume command runs on the host in the pane's saved directory through `safe-pi`, which re-enters the sandbox and forwards `--session` to Pi inside it.

## Open questions (all answered below)

- Is Pi's session id (the UUID) stable and resolvable with `--session <id>` both from the host and inside the sandbox, or must the resume command use a path?
- If it must be a path: should it be the host path (needs a container→host mapping) or the container-only path (invalid on the host)? Which layer derives it?
- Does the id stay valid across a Pi session fork/branch, and does the command need the model or other flags for parity?
- Does the reporter need to re-report the resume command whenever the session changes (`session_start`, `agent_start`)?

All four are answered in the Pi source below; the criteria stand.

## Acceptance criteria

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

### Answers from the Pi source (2026-10-10)

Read from the installed Pi (`@earendil-works/pi-coding-agent`, `dist/`). All
four open questions resolve in favour of `safe-pi --session <uuid>`:

- **The id is stable, and a full UUID cannot resolve to another session.**
  `SessionManager.newSession()` assigns a UUIDv7 (`createSessionId()`), writes it
  in the session header, and returns it from `getSessionId()`; it does not change
  for the life of the session file (the file name is
  `<timestamp>_<id>.jsonl`). For a non-path argument, `--session` resolves by
  exact id first (`SessionManager.findById` reads session headers), then by
  `startsWith` prefix, then across projects. A 36-character UUID cannot be a
  strict prefix of another UUID, so with the file present the exact match is the
  only candidate; and exact is tried before prefix.
- **The argument must be the id, not a path.** `safe-pi` never resolves it on
  the host — it forwards it to Pi inside the container, where the wrapper sets
  `PI_CODING_AGENT_SESSION_DIR` to the container-only project directory. Pi
  looks the id up there, and the cwd filter passes because the session header
  records the host path, which is also the container's working directory. A host
  path does not exist inside the container and a container path does not exist
  on the host; the id is the only form valid on both.
- **A fork/branch does not invalidate it, and no extra flags are needed for
  parity.** In-session tree navigation (`/tree`) keeps the session file and id.
  An in-process new/fork/resume swaps the session manager and emits
  `session_start` with reason `new`/`fork`/`resume`, which the reporter already
  handles, and `agent_start` refreshes the reference every turn — so ticket 13's
  re-report triggers are the right ones and need no change. The model and
  thinking level are recorded on the session branch (`model_change`) and restored
  when the session opens, so a bare `--session <id>` matches what `-c` restored.
- **`--session-id` was the alternative, and was rejected.** It also opens the
  exact project session but *creates* it when missing, so a restart before the
  first message is persisted would open an empty session with the same id where
  `--session` exits with `No session found matching`. The contract is "the same
  conversation": a visible failure beats a silently empty session, and the file
  is absent only until the first user or assistant message is written.

Decision: the reporter attaches `["safe-pi", "--session", <uuid>]`, falling
back to `["safe-pi", "-c"]` only when it has no session id to name.
