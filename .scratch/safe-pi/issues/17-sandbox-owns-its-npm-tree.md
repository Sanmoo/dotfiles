# 17 — On macOS the sandbox loads the host's darwin-only npm tree, so native packages fail

**What to build:** On macOS (Colima, ADR 0008) the sandbox must load Pi's npm
packages with native bindings built for the sandbox's own platform
(linux/aarch64). Today Pi refuses to start:

```text
Error: Failed to load extension "/Users/samuel.santos/.pi/agent/npm/node_modules/pi-md-export/extensions/md.ts":
Failed to load extension: Cannot find native binding. npm has a bug related to
optional dependencies (https://github.com/npm/cli/issues/4828). ...
Hint: Start without extensions using "pi -ne".
```

The proposed direction is for the sandbox to own its npm tree. A per-user
Docker volume is mounted at `$HOME/.pi/agent/npm`. The entrypoint installs into
it with `npm ci`, using the host's `package.json` and `package-lock.json`. That
happens only when the lock changed since the last install, the same probe-then-
install convergence the toolchain volume already uses. The host's tree stays
untouched and remains read-only from the sandbox's side.

**Status:** needs-triage

- [ ] On a Darwin host, `safe-pi` starts Pi with every package in
      `~/.pi/agent/settings.json` loaded, including `pi-md-export`
      (`@mariozechner/clipboard`), `pi-lens` (`@ast-grep/napi`), and the
      packages that depend on `@napi-rs/keyring`.
- [ ] The sandbox's npm tree is installed inside the container from the host's
      `package.json` and `package-lock.json`. The host's `~/.pi/agent/npm` is
      never written by the sandbox. It is mounted read-only only as the source
      of those two files, not at its own path.
- [ ] Convergence: a start whose host lock matches the one last installed
      installs nothing and prints nothing, so a steady start stays a steady
      start. A changed lock (`pi install`, `pi update`, `pi remove` on the host)
      is reinstalled on the next start. `--prepare` converges the npm tree too.
- [ ] A failed install is a warning that names the step, and the sandbox starts
      with the tree it already has, as toolchain convergence does. Under
      `--prepare`, a failed install is an error.
- [ ] The tree is mounted at `$HOME/.pi/agent/npm`, so the relative symlinks in
      `~/.pi/agent/extensions` and Pi's own package resolution keep working.
- [ ] `tests/safe-pi-wrapper-test.sh` and `tests/safe-pi-entrypoint-test.sh`
      cover: the volume and the read-only lock source in the Docker invocation,
      install on a first start, no install on an unchanged lock, reinstall on a
      changed lock, and the warning on a failed install.
- [ ] Verified on this macOS host and recorded here: `safe-pi` starts without
      `-ne` and `pi-md-export` and `pi-lens` load. A steady start's time is
      measured against the one before this ticket.
- [ ] The README's safe-pi resources table and the usage guide name the volume.
      An ADR (or an addendum to 0002 or 0008) records the decision, and
      `CONTEXT.md` gains the term if a new one is introduced.

## What is known

Observed on 2026-10-10 on this host (macOS arm64, Colima 0.10.1 `aarch64`,
`docker info` → `aarch64 linux`, npm 10.9.8 on the host):

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
  needs, so an `npm ci` inside the container resolves them from the same lock:
  `@ast-grep/cli-linux-arm64-gnu`, `@ast-grep/napi-linux-arm64-gnu`,
  `@esbuild/linux-arm64`, `@mariozechner/clipboard-linux-arm64-gnu`,
  `@napi-rs/keyring-linux-arm64-gnu`, `recheck-linux-arm64`.
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

## Open questions

- Does the sandbox own its npm tree on every host, or only under a Daemon VM?
  Doing it everywhere keeps one contract and also removes the glibc/arch
  coupling on Linux. The cost is a first-start install and one more volume on a
  host where the shared tree already works.
- Volume or bind mount? A named volume (`safe-pi-npm-u<uid>`, like the toolchain
  volume) keeps sandbox-written code off the host filesystem. A host directory
  under `~/.cache/safe-pi/` (like the transpile cache) is easier to inspect and
  remove.
- What is the convergence key: a hash of `package-lock.json`, of
  `package.json` plus the lock, or also the image's Node and npm versions? A
  Node major bump could change ABI-sensitive prebuilt binaries.
- `npm ci` runs install scripts from the package set inside the sandbox, with
  network access. That is the same trust the host already gives these packages,
  but it now happens on every lock change. Should it be `--ignore-scripts`, and
  do any of the current packages need their scripts?
- Pi also installs packages from git into `~/.pi/agent/git/` (present on this
  host). The wrapper does not mount it separately; it reaches the sandbox only
  through the read-write `~/.pi/agent` mount. Can it carry native dependencies
  too? If so, it needs the same treatment or an explicit exclusion.
- Does the transpile cache (ADR 0005) need to be invalidated when the sandbox's
  tree changes? jiti keys entries by source content, so probably not, but this
  should be confirmed.
- How should `pi install` inside the sandbox fail? Today the read-only mount
  rejects it. With a writable sandbox tree it would succeed and then be
  overwritten by the next convergence from the host lock.

## Comments
