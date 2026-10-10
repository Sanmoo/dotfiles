# 18 — The sandbox can write the host's git-installed Pi packages

**What to build:** `~/.pi/agent/git/`, where Pi clones packages installed with
`pi install git:...`, must be read-only inside the sandbox. ADR 0002 holds Pi
packages read-only for this reason: "so that a bad turn cannot persist code
changes (extensions, Pi packages) into the host setup". Today only
`~/.pi/agent/extensions` and `~/.pi/agent/npm` get read-only sub-mounts. `git/`
is reached through the read-write agent-directory mount, so a sandboxed turn can
edit code the host Pi loads on its next start.

**Status:** needs-triage

- [ ] The wrapper mounts `$HOME/.pi/agent/git` read-only at its own path when it
      exists, like `extensions/`. It is listed as a missing optional mount when
      it does not exist.
- [ ] `tests/safe-pi-wrapper-test.sh` covers the read-only mount, and its absence
      when the directory is missing.
- [ ] Verified on this host: writing under `~/.pi/agent/git/` from
      `safe-pi --shell` fails with a read-only file system error.
- [ ] The README's resources table lists the mount.

## What is known

Found on 2026-10-10 while settling ticket 17:

- `~/.pi/agent/git/github.com/obra/superpowers` exists on the macOS host. It is
  not in `~/.pi/agent/settings.json`'s `packages`, so nothing loads it today. It
  has no `node_modules` and no native bindings.
- The wrapper's read-only sub-mounts are `add_mount "$PI_AGENT_DIR/extensions"
  ... ro` and `add_mount "$PI_AGENT_DIR/npm" ... ro` (`pi/.local/bin/safe-pi`).
  There is none for `git/`.
- Pi resolves a git source to `<agentDir>/git/<host>/<path>`. It installs a
  missing one on start, and it runs `npm install` inside a cloned package that
  has dependencies (`repairMissingGitDependencies` in Pi's
  `core/package-manager.js`). A read-only mount therefore also blocks those
  writes from the sandbox.

## Open questions

- A git package with a missing clone, or missing dependencies, makes Pi in the
  sandbox try to write under `git/`. With the mount read-only, that fails. Is
  that acceptable, as it is today for npm under ADR 0002? Or should git packages
  get a sandbox-owned tree like ADR 0009's, which would matter only if one
  carried native bindings?

## Comments
