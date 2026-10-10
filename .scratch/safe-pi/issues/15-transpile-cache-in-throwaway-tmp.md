# 15 — A steady start recompiles the Pi extensions, because jiti's cache is thrown away with `/tmp`

**What to build:** A `safe-pi` start whose extension set is unchanged must reach Pi's first frame as fast as the host's `pi` does, the way the usage guide already describes a steady start ("about three seconds, almost all of it container startup"). Today it takes about fifteen, because the TypeScript extensions Pi loads are recompiled from scratch on every start.

**Status:** ready-for-agent

- [ ] A second `safe-pi` start reaches Pi's first frame in the low single-digit seconds, measurably no slower than the host `pi` measured the same way.
- [ ] The compilation cache that makes it fast survives the container that wrote it, and it is private to the sandbox: nothing the sandbox writes is code the host Pi executes.
- [ ] The `docker` boundary test asserts the cache mount and its mode, and the usage guide names the cache and where it lives.

## What is known

Measured on this machine — `safe-pi` (all extensions, `--offline`), Pi's first drawn
frame inside a 120×32 tmux pane, five runs: **14.3 s, 16.6 s, 17.0 s**; the host's
`pi`, same harness: **3.8 s, 4.4 s**.

- `safe-pi --offline --no-extensions` reaches the first frame in 3.5 s, and with
  only `pi-lens` loaded 12.5 s: the cost is the extensions, not Docker, not the
  entrypoint's convergence (`--prepare` is 251 ms), not the image's Pi
  (`pi --version` in the container is 460 ms).
- A Node CPU profile of the container's Pi (`node --cpu-prof`, only `pi-lens`
  loaded) attributes seconds 0–9 of the process to `jiti`'s bundled Babel at a
  sustained ~900 ms of CPU per second — `visitQueue`, `visit`, `traverseNode` —
  then goes idle at second 10, when `pi-lens` loads.
- The cause is where jiti keeps that compiled output: `prepareCacheDir` in
  `jiti/dist/jiti.cjs` resolves `fsCache === true` to `<pkg>/node_modules/.cache/jiti`
  when that directory exists and to `os.tmpdir()/jiti` otherwise, and the
  extension packages have no `node_modules` of their own, so every extension is
  cached at `/tmp/jiti`. On the host that directory holds 264 compiled modules
  and the host Pi is fast; `safe-pi` runs the container with `--tmpfs /tmp`, so
  the sandbox starts with it empty and recompiles everything.
- jiti's cache is validated by content, not by timestamp: a cached file is used
  only when it ends with `/* v9-<hash of the source> */`, so reusing a persisted
  cache cannot serve stale code after an extension or Pi update.
- Verified fix: binding a persistent directory at `/tmp/jiti` over the tmpfs
  (Docker orders nested mounts by depth, so the bind wins) takes the same
  measurement to **2.4 s, 2.6 s, 2.7 s** on warm runs; the first run against a
  cold cache is 16.0 s and fills it with 187 files.

## Open questions

- Should the cache be shared with the host's own `/tmp/jiti`? It would make even
  the first sandbox start warm, since the host has already compiled the same
  extensions. Against it: the cached files are modules the host Pi loads, so a
  sandboxed turn could replace one and have the host execute it, which is the
  isolation the read-only extensions and npm mounts exist to provide.
- Does the cache belong under the Pi agent directory (already mounted) or a
  dedicated `~/.cache` path?
- Is a Docker named volume better than a host directory? A fresh named volume is
  root-owned, so jiti's writability check would fail and disable its cache
  unless the image seeds the path as the invoking user.

## Comments

### Decision (2026-10-09)

- **Persist the cache; leave the temporary directory otherwise throwaway.** The
  cache is bound at `/tmp/jiti` over `--tmpfs /tmp`, so only the compiled
  extensions survive and every other temporary file stays ephemeral.
- **The sandbox keeps its own cache.** Sharing the host's `/tmp/jiti` was
  rejected: a cache entry is a module the *host* Pi executes, and the sandbox's
  extensions and npm packages are mounted read-only precisely so that a bad turn
  cannot persist code into the host setup. A sandbox-writable directory the host
  Pi reads would hand that guarantee back. The cost is that the very first
  sandbox start after this change compiles once.
- **A host directory, not a named volume.** jiti creates its cache directory and
  refuses it unless it is writable by the sandbox user; a fresh named volume is
  root-owned, and the image cannot seed `/tmp/jiti` for the same reason the
  tmpfs exists. A directory created by the wrapper as the invoking user needs no
  seeding and matches the shape of the other host mounts.
- **The container's jiti keeps deciding the path.** No `TMPDIR` override and no
  configuration: `/tmp/jiti` is where jiti looks, and the mount is what makes it
  persist. Persisting all of `TMPDIR` was rejected — it would widen what survives
  a start far beyond the cache this ticket is about, against the contract's
  throwaway temporary directory.
- **No image change.** This is wrapper-only, so the entrypoint label does not
  move and an existing image is not rebuilt.
