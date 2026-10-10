# The sandbox installs its own Pi packages from the host's lock

ADR 0002 mounts the host's Pi package installation (`~/.pi/agent/npm`) into the sandbox, read-only and at its own path. That works only while the host and the image share a platform. Packages with native parts carry one prebuilt binding per platform, and npm installs only the host's. On macOS the host tree holds `darwin-arm64` bindings, the sandbox is `linux/aarch64` in the Daemon VM, and Pi refuses to start (`Cannot find native binding`, first from `@mariozechner/clipboard`, then `@ast-grep/napi` and `@napi-rs/keyring`). On Linux it holds only by coincidence of architecture and libc.

The decision is that the sandbox keeps its own sandbox package tree on every host and converges it the way it converges the declared environment:

- The wrapper mounts a host directory, `$HOME/.cache/safe-pi/npm`, at `$HOME/.pi/agent/npm`. The wrapper creates it as the invoking user, as it does for the transpile cache (ADR 0005). The mount keeps host path parity and hides the host's own tree from the sandbox.
- The host's `package.json` and `package-lock.json` are mounted read-only at a container-only path. The entrypoint installs from them with `npm ci --legacy-peer-deps`, the flag Pi's own installs use, so the sandbox resolves exactly the versions the host locked, with the bindings for its own platform.
- The convergence key is the hash of those two files plus the image's Node ABI (`process.versions.modules`). A stamp holding the key is written only after a successful install. A start whose stamp matches installs nothing and prints nothing, so it stays a steady start. A missing or different stamp reinstalls, including after an interrupted install or an image with another Node major.
- Installs run under a lock, as toolchain convergence does, so concurrent starts do not install over each other. A host without a lock has nothing declared, and convergence skips silently.
- A failed install is a warning, and the sandbox starts with the tree it has. Under `--prepare` it is an error.

## Considered Options

- **Only under a Daemon VM, or only when the platforms differ.** Rejected. One contract is one path to test and document. The Linux case is correct only by coincidence, and the cost there is one install of a few seconds and about 400 MB of disk.
- **Let Pi install the missing packages itself** into an empty writable tree (Pi installs a missing npm source on start without asking). Rejected as the mechanism: it installs the settings' unpinned specs, so the sandbox would run different versions from the host. It is kept as the fallback when convergence fails (see Consequences).
- **Install from the host with `npm install --os=linux --cpu=...`.** Rejected: install scripts would run on the host, and the wrapper would depend on the host's npm.
- **Add the Linux bindings to the host's own tree** (`npm install --no-save --os=darwin --os=linux ...`). Rejected: the next `pi install` or `pi update` on the host can prune them. It also mixes the sandbox's needs into host state the sandbox is meant to leave alone. It remains a stop-gap.
- **A named Docker volume.** Rejected for the reason ADR 0005 recorded: a fresh named volume is root-owned. This one would also be nested inside the agent-directory bind, where seeding its ownership from the image is unverified.
- **`npm ci --ignore-scripts`.** Rejected: these are the packages the host already trusted, and their scripts already ran on the host with more privilege than the sandbox has. Skipping them would only make a package that needs one fail in the sandbox alone.
- **One tree per key**, with the wrapper choosing `~/.cache/safe-pi/npm/<key>`, so a running sandbox keeps its tree while another reinstalls. Rejected for now: a lock change is rare and usually made by the user on the host. A reinstall in place costs at most a late module load in an already-open sandbox, recovered by restarting it.

## Consequences

- The read-only npm mount of ADR 0002 no longer holds: the sandbox writes its own tree. The host's tree is still unreachable from the sandbox, which was the mount's purpose. The sandbox package tree is sandbox state the host never executes, like the transpile cache.
- A reinstall replaces the tree in place. An open sandbox that loads a package module after another start reinstalled can fail mid-session.
- When convergence fails and the tree is empty, Pi in the sandbox installs the settings' packages itself, at their latest versions. The stamp stays absent, so the next start converges back to the host's lock.
- `pi install`, `update` and `remove` inside the sandbox work against the sandbox package tree, and the shared `settings.json`, which was already writable. The host's lock stays the source of truth. A package installed only in the sandbox lasts until the next reconvergence, and the host Pi installs a newly declared package itself on its next start.
- The transpile cache needs no invalidation when the tree changes: jiti keys an entry by the module's path and validates it against the source's hash.
- The first start after this change installs the tree: about 7 s on the macOS host, from a populated npm cache.
