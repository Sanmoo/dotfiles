# The sandbox keeps its own extension transpile cache, bound over the throwaway temporary directory

Pi loads its TypeScript extensions through jiti, which compiles them with Babel and caches the compiled modules on disk. `prepareCacheDir` in `jiti/dist/jiti.cjs` resolves the cache to `<package>/node_modules/.cache/jiti` when that directory exists and to `os.tmpdir()/jiti` otherwise; the installed extension packages carry no `node_modules` of their own, so every extension Pi loads is cached at `/tmp/jiti`.

ADR 0002 runs the sandbox with `--tmpfs /tmp` so temporary files are thrown away with the container. The cache lives there, so a sandbox start begins with an empty cache and recompiles the whole extension set: measured inside the sandbox, 14.3–17.0 s from launch to Pi's first drawn frame against 3.8–4.4 s for the host's `pi`, with a CPU profile attributing seconds 0–9 entirely to jiti's bundled Babel (`visitQueue`, `visit`, `traverseNode`) at a sustained ~900 ms of CPU per second. Docker, the entrypoint's convergence, and the image's own Pi are not implicated: `--no-extensions` starts in 3.5 s, `--prepare` converges in 251 ms, and `pi --version` in the container answers in 460 ms. The consequence is a sandbox that costs about ten seconds more than the host for every start, which the usage guide already contradicted by describing a steady start as "about three seconds, almost all of it container startup".

The decision is that the sandbox persists its own transpile cache in a host directory bound at `/tmp/jiti`, over the tmpfs:

- The wrapper's contract gains one mount: a host directory at `$HOME/.cache/safe-pi/jiti`, mounted read-write at `/tmp/jiti`. Docker orders nested mounts by destination depth, so the bind wins over the tmpfs and the rest of `/tmp` stays ephemeral.
- The directory is created by the wrapper as the invoking user, like the agent and sessions directories, because Docker creates a missing bind source as a root-owned directory and jiti refuses a cache directory it cannot write.
- The container's jiti still decides the path; no `TMPDIR` override and no jiti configuration are involved. `/tmp/jiti` is where it looks, and the mount is what makes it persist.
- No image change: the entrypoint is untouched, so its label does not move and an existing image is not rebuilt.

## Considered Options

- **Leave it, and correct the usage guide's description of a steady start.** Rejected: the guide's number is the acceptance surface for a start that has nothing to install, and ten seconds of Babel per start is a defect with a one-mount fix, not a property to document.
- **Share the host's own `/tmp/jiti` by mounting it.** Attractive because the host Pi has already compiled the same extensions, so the sandbox's first start would be warm with no cold run at all. Rejected on the isolation boundary: a cache entry is a module the host Pi loads, so a sandbox-writable directory the host reads is a path for a sandboxed turn to persist code that the host then executes. jiti validates a cache entry by the source hash in its trailing marker, but the sources are readable from inside the sandbox, so the marker is not a defence. The read-only extension and npm package mounts exist to keep sandboxed turns from persisting code into the host setup, and this would hand that back for ten seconds of startup.
- **Persist `TMPDIR` (or all of `/tmp`).** Rejected: it widens what survives a start far beyond the cache, against the contract's throwaway temporary directory, and it changes temporary-file semantics for every tool in the sandbox rather than for the one directory that needs to persist.
- **A dedicated Docker named volume mounted at `/tmp/jiti`.** Rejected: a fresh named volume is root-owned, jiti's writability check would fail and silently disable its filesystem cache, and the image cannot seed the path as the invoking user because `/tmp` is shadowed by the tmpfs at runtime.
- **Turn jiti's filesystem cache off entirely and accept the recompilation.** Rejected: it is the same ten seconds per start, with no way to make a later start cheaper.
- **Cache compiled output in the image, or precompile the extensions at build time.** Rejected: the extensions are host state mounted read-only, not image content, and they change whenever the host installs a package; an image-baked cache would be stale on arrival and would rebuild the image on every extension change.

## Consequences

- A warm sandbox start reaches Pi's first frame in the low single-digit seconds — measured 2.4–2.7 s against the host's 3.8–4.4 s — because the sandbox's Pi is installed in the image and pays no package resolution.
- The very first start after this change, and any start after the sandbox's cache is removed, still compiles the extension set once (measured 16.0 s, filling the cache with 187 modules). Only newly added or changed extensions are compiled afterwards, since jiti validates a cache entry against the source's hash, not its timestamp.
- The cache is sandbox state, not Pi state: the host Pi keeps using its own `/tmp/jiti`, and removing `$HOME/.cache/safe-pi/jiti` costs one recompilation and nothing else.
- The mount is a second path where the sandbox is writable under `$HOME` beyond the working repository, the agent directory, and the pi-lens directory. It is a cache the sandbox compiles for itself, and the host executes nothing from it.
