# 17 — On macOS the sandbox loads the host's darwin-only npm tree, so native packages fail

**What to build:** The sandbox keeps its own sandbox package tree on every host,
installed inside the sandbox from the host's package lock, so the native parts
of Pi's packages match the sandbox's platform (ADR 0009). Today, on macOS
(Colima, ADR 0008), the sandbox loads the host's darwin-only tree and Pi refuses
to start:

```text
Error: Failed to load extension "/Users/samuel.santos/.pi/agent/npm/node_modules/pi-md-export/extensions/md.ts":
Failed to load extension: Cannot find native binding. npm has a bug related to
optional dependencies (https://github.com/npm/cli/issues/4828). ...
Hint: Start without extensions using "pi -ne".
```

**Status:** resolved

- [x] **Mounts.** The wrapper creates `$HOME/.cache/safe-pi/npm` as the invoking
      user and binds it at `$HOME/.pi/agent/npm`, replacing the read-only mount
      of the host's tree. The host's `~/.pi/agent/npm/package.json` and
      `package-lock.json` are mounted read-only at a container-only path
      (`/run/safe-pi/host-npm/`). Each is mounted only when it exists. The
      host's tree is not reachable from the sandbox. `--dry-run` shows the
      mounts, and `--dry-run` creates nothing on the host.
- [x] **Convergence.** The entrypoint converges the sandbox package tree on
      every start, the debug shell included, alongside the toolchain:
      - The key is a hash of the host's `package.json` and `package-lock.json`
        plus the image's Node ABI (`process.versions.modules`).
      - A stamp in the tree holds the key of the last successful install. It is
        written only after `npm ci` succeeds.
      - A matching stamp installs nothing and prints nothing (a steady start).
        A missing or different stamp runs `npm ci --legacy-peer-deps` in the
        tree, with install scripts enabled, and shows its progress.
      - Installs run under a `flock`, so concurrent starts do not install over
        each other. A second start waits, then finds the tree converged.
      - With no host lock, convergence skips silently.
- [x] **Failure.** A failed install warns with a message that names the step,
      and the sandbox starts with the tree it already has, as toolchain
      convergence does. Under `--prepare`, a failed install fails the command,
      and `--prepare` converges the package tree as well as the toolchain.
- [x] **Image.** The `safe-pi.entrypoint` label is bumped, so existing images
      rebuild.
- [x] **Tests.** `tests/safe-pi-wrapper-test.sh` covers the cache-directory bind
      at the npm path, the read-only lock sources, their absence when the host
      has no lock, and the directory being created by the wrapper but not by a
      dry run. `tests/safe-pi-entrypoint-test.sh` covers, with `npm` stubbed:
      - install on a first start;
      - nothing on an unchanged key, with no output;
      - reinstall on a changed lock and on a changed Node ABI;
      - no stamp after a failed install;
      - the warning on a failed install, and the error under `--prepare`;
      - the silent skip without a host lock.
- [x] **Verified on this macOS host and recorded here.** `safe-pi` starts
      without `-ne`. `pi-md-export`, `pi-lens` and the keyring users load. A
      steady start installs nothing and its time is measured. `safe-pi
      --prepare` converges the tree.
- [x] **Docs.** The README's safe-pi section and the usage guide's table of
      resources name the sandbox package tree and its directory. "Starting
      over" mentions removing it. `CONTEXT.md` and ADR 0009 are already
      written.

## What is known

Observed on 2026-10-10 on this host (macOS arm64, Colima 0.10.1 `aarch64`,
`docker info` → `aarch64 linux`, npm 10.9.8 and Node 22.23.2 on the host, npm
11.20.0 and Node 26.11.1 in the image):

- The wrapper mounts the host's tree at its own path, read-only:
  `add_mount "$PI_AGENT_DIR/npm" "$PI_AGENT_DIR/npm" ro`
  (`pi/.local/bin/safe-pi`, "Installed code is held immutable ...").
- On macOS, npm installed only the darwin variants of the platform-specific
  optional dependencies, which is correct behaviour for the host:
  `@ast-grep/cli-darwin-arm64`, `@ast-grep/napi-darwin-arm64`,
  `@esbuild/darwin-arm64`, `@mariozechner/clipboard-darwin-arm64`,
  `@mariozechner/clipboard-darwin-universal`, `@napi-rs/keyring-darwin-arm64`,
  and `fsevents`.
- The host's `package-lock.json` already lists the Linux variants the sandbox
  needs: `@ast-grep/cli-linux-arm64-gnu`, `@ast-grep/napi-linux-arm64-gnu`,
  `@esbuild/linux-arm64`, `@mariozechner/clipboard-linux-arm64-gnu`,
  `@napi-rs/keyring-linux-arm64-gnu`, `recheck-linux-arm64`.
- Measured: `npm ci --legacy-peer-deps --no-fund --no-audit` in
  `safe-pi:current-u502`, from copies of the host's `package.json` and
  `package-lock.json`, took about 7 s and produced 412 MB of `node_modules`,
  with the `linux-arm64-gnu` and `-musl` variants. `require("@mariozechner/clipboard")`
  then loaded.
- Pi installs npm packages with `npm install <spec> --prefix ~/.pi/agent/npm
  --legacy-peer-deps` (`getNpmInstallArgs` in Pi's `core/package-manager.js`).
  `npm ci` needs the same flag to honour the lock.
- No package in the current lock has `hasInstallScript`.
- On start, Pi installs a configured npm package that is missing or at the wrong
  version, without asking (`resolvePackageSources` → `installMissing`, no
  `onMissing` callback). `PI_OFFLINE=1` turns that off, along with Pi's other
  downloads.
- jiti names a cache entry after the module's path and validates it against a
  hash of the source (`/* v9-<hash> */`), so the transpile cache needs no
  invalidation when the tree changes.
- `pi-md-export` is only the first package to fail. Pi stops at the first
  extension that fails to load, so `pi-lens` (ast-grep) and the keyring users
  would fail next.
- On Linux the host and the sandbox share a platform (and glibc, with the
  `node:26-bookworm-slim` base), so the host's tree loads. The macOS gap was not
  caught by ticket 16's verification.
- Workaround until this lands (outside the repository, not durable):
  `cd ~/.pi/agent/npm && npm install --no-save --os=darwin --os=linux
  --cpu=arm64 --libc=glibc` adds the Linux variants beside the darwin ones. A
  later `pi install`/`pi update` on the host may prune them.
- `pi-deere` links `~/.pi-deere/agent/npm` to `~/.pi/agent/npm` (README, "What
  is shared and what is private"). This ticket does not change the host tree,
  so `pi-deere` is unaffected.

## Comments

### Decision (2026-10-10)

Settled in a grilling session; recorded in ADR 0009 (with a pointer in ADR
0002), and in `CONTEXT.md` (the new term Sandbox package tree; Converge and
Steady start widened to cover it).

- **Scope:** every host, not only under a Daemon VM. One contract; Linux works
  today by coincidence of platform.
- **Installer:** the entrypoint, with `npm ci --legacy-peer-deps` from the host's
  `package.json` and `package-lock.json`, mounted read-only at a container-only
  path. Pi's own install of missing packages (unpinned specs) and a host-side
  cross-platform install were rejected.
- **Storage:** a host directory, `~/.cache/safe-pi/npm`, bound at
  `~/.pi/agent/npm`, like the transpile cache (ADR 0005). A named volume would
  be root-owned and nested in the agent-directory bind.
- **Install scripts:** enabled. They already ran on the host, with more
  privilege.
- **Key:** hash of `package.json` + `package-lock.json` plus the image's Node
  ABI. The stamp is written only after a successful install.
- **Concurrency:** reinstall in place under `flock`. An already-open sandbox can
  fail a late module load after another start reinstalls; accepted. One tree
  per key was rejected for now.
- **Failure:** warn and start with the tree it has. Pi itself installs into an
  empty tree as a fallback (no `PI_OFFLINE`), and the next start converges back
  to the lock. `--prepare` fails.
- **`pi install` in the sandbox:** allowed. The host's lock stays the source of
  truth; a sandbox-only install lasts until the next reconvergence.
- **No host lock:** nothing is declared, so convergence skips silently.
- **Out of scope:** `~/.pi/agent/git/` is writable from the sandbox. That is an
  isolation gap, not a platform one, and it goes to ticket 18.
- **Settled by fact:** the transpile cache needs no invalidation (jiti validates
  by source hash).

### Implementation (2026-10-10)

Integrated into `main` as `3d85fef` and `fa2b477`. `tests/run --full` ended
`FULL GATE: PASS` (28 of 28 units).

Verified on this macOS host (Colima aarch64, image rebuilt for entrypoint 9):

- `safe-pi --prepare` converged the tree: `added 279 packages in 10s` on the
  first run (cold npm cache, the tree installed with the image's npm 11.20.0
  and Node 26), then stamp written in `~/.cache/safe-pi/npm`.
- A steady `safe-pi --prepare` took 0.58 s end to end and printed nothing.
- `require()` of `@mariozechner/clipboard`, `@napi-rs/keyring` and
  `@ast-grep/napi` loaded in the sandbox; `pi-md-export` and `pi-lens` are in the
  tree with the `linux-arm64-gnu` bindings.
- `safe-pi --offline -p ...` starts without `-ne` and no extension fails to load
  (the only output was an unrelated expired Anthropic OAuth refresh), in about
  2.1 s. The host's `~/.pi/agent/npm` was untouched (still darwin).
- npm 11.20 prints an `install-scripts ... not yet covered by allowScripts`
  warning for `@ast-grep/cli`, `esbuild` and `pi-rtk-optimizer`; the scripts did
  run (native `esbuild` and `ast-grep` binaries are in place). The warning is
  advisory today; a later npm that blocks unapproved scripts would need an
  `allowScripts` entry.

Notes from review:

- `npm ci` removes `node_modules` first, so a failed reinstall can leave a
  partial tree; the warning says "starting with whatever the tree holds" and Pi
  installs missing packages itself (ADR 0009).
- The wrapper also creates the host's `~/.pi/agent/npm` directory (empty if
  absent) so the daemon does not create the mount point root-owned.
- The entrypoint honours `SAFE_PI_HOST_NPM_DIR` as a test seam; convergence also
  skips when `package.json` is missing.
- The usage guide's "table of resources" is the README's "What the sandbox sees"
  list, as in ticket 16.
