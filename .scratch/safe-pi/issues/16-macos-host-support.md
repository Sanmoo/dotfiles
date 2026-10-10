# 16 — `safe-pi` cannot start on macOS, where the Docker daemon runs in a VM

**What to build:** `safe-pi` must start on the macOS host (Homebrew `docker` CLI
against Colima) with the same contract it has on Linux: the sandbox user's home
is the host's, every bind is a `--mount type=bind`, and the invoking shell's SSH
agent and Herdr's socket reach the sandbox through a socket relay over the
Colima VM's SSH (ADR 0008). Today the container never starts: the wrapper
bind-mounts the host's SSH agent socket, and the Daemon VM cannot see it.

This is a scope change. The spec lists "macOS support (`pi-mac`)" under *Out of
Scope*; this ticket brings macOS with Colima in. The spec stays as archive; ADR
0008 and the README are the living record.

**Status:** resolved

- [x] On Darwin the wrapper identifies the Colima profile from `docker info
      --format '{{.Name}}'` (`colima`, or `colima-<profile>`, which is also the
      `Host` alias in `~/.colima/ssh_config`), and refuses any other daemon with
      `safe-pi on macOS supports Colima only`. Linux behaviour is unchanged
      apart from the `--mount` switch.
- [x] A run or `--shell` start on Colima opens its own SSH connection to the VM
      (its own control path, not Lima's master) with one remote unix-socket
      forward per host socket present — the invoking shell's `$SSH_AUTH_SOCK`,
      and `$HERDR_SOCKET_PATH` when the Herdr variables are set — into a private
      per-start directory in the VM; mounts the forwarded sockets at the
      container paths the contract already uses (`/run/safe-pi/ssh-agent.sock`,
      and the reporter's `SAFE_PI_HERDR_SOCKET_PATH`); and closes the connection
      and removes the directory when the sandbox exits. The connection is opened
      alongside the pre-start checks to hide its ~0.9 s.
- [x] A relay that cannot be opened is a per-socket warning (`safe-pi: SSH agent
      unavailable in the sandbox: <reason>`, and the Herdr equivalent), and the
      sandbox starts without that socket.
- [x] `--prepare` opens no relay. `--dry-run` prints the relay command before the
      Docker invocation and runs neither.
- [x] Every bind the wrapper emits is `--mount type=bind,...`, so a source the
      daemon cannot see fails as a missing source instead of becoming a
      directory the daemon creates. The toolchain volume and the tmpfs keep
      their current form.
- [x] The image creates the sandbox user with the host's `$HOME` (a build
      argument, recorded in a `safe-pi.home` label), and seeds the mount points
      under it; an image whose label differs from the invoking `$HOME` is stale
      and rebuilt. The `safe-pi.entrypoint` label is bumped so existing images
      rebuild.
- [x] `tests/safe-pi-wrapper-test.sh` covers, with `uname`, `ssh` and
      `docker info` stubbed: Linux unchanged except `--mount`; Darwin with the
      default and a named Colima profile; Darwin with another daemon refused; a
      failed relay warning and starting without the socket; the dry run printing
      the relay; `--prepare` opening none; the home build argument and label; a
      stale-home image rebuilt.
- [x] Verified on this macOS host and recorded here: `ssh-add -l` lists the
      invoking shell's key and `git push` over SSH works from the sandbox; the
      Herdr pane is attributed to Pi; a Herdr server restart brings the pane
      back inside the sandbox; `safe-pi --prepare` converges the toolchain
      volume.
- [x] The README gains a macOS section (Colima only, what the relay does, the
      ~0.9 s it adds), and the usage guide's table of resources names the relay.

## What is known

Observed on this machine (macOS arm64, Docker CLI 29.5.2, Colima 0.10.1 with
`vmType: vz`, `mountType: virtiofs`, `mounts: []` so only `$HOME` is shared):

```text
error mounting "/var/folders/p0/.../T/ssh-8zwTvy2BLAHm/agent.48523" to rootfs at
"/run/safe-pi/ssh-agent.sock": ... not a directory: Are you trying to mount a
directory onto a file (or vice-versa)?
```

- The wrapper mounts `$SSH_AUTH_SOCK` with `--volume` whenever it is a socket on
  the host (`pi/.local/bin/safe-pi`, "The SSH agent socket is mounted only when
  the host provides one"). On macOS that path is under `/var/folders`, which the
  VM does not share, so the daemon resolves it inside the VM, finds nothing, and
  `--volume` creates it as a directory. Mounting that directory over the
  image's `/run/safe-pi/ssh-agent.sock` file fails. The stray directory
  `.../ssh-8zwTvy2BLAHm/agent.48523` was left behind in the VM.
- Sharing the path would not help: a unix socket on a virtiofs share does not
  connect to the host process that listens on it.
- The same applies to Herdr: `HERDR_SOCKET_PATH` is
  `~/.config/herdr/herdr.sock`, inside the shared `$HOME`, but the reporter's
  connection cannot reach the host Herdr through virtiofs. The reporter tolerates
  an unreachable socket silently, so the pane would simply not be attributed.
- Lima (under Colima) has agent forwarding: with `forwardAgent: true` in
  `~/.colima/default/colima.yaml` (or `colima start --ssh-agent`) it links the
  forwarded agent to the static VM path `/run/host-services/ssh-auth.sock` — the
  string `linking ssh auth socket to static location
  /run/host-services/ssh-auth.sock` is in `limactl`. Docker Desktop exposes the
  same path. This machine has `forwardAgent: false`, and the path does not exist
  in the VM today. Changing it needs `colima stop && colima start`.
- The forwarded agent is the one in the environment `colima start` ran in. This
  machine runs about ten `ssh-agent -s` processes (one per shell, apparently), so
  which agent Colima forwards depends on where it was started.
- `docker info` reports `OperatingSystem: Ubuntu 24.04.4 LTS`, `Name: colima`;
  Docker Desktop reports `Docker Desktop`. `uname -s` on the host is `Darwin`.
- Already fixed on the way here (da9350b): the image used `COPY --chmod`, which
  the legacy builder rejects; this host's CLI has no `buildx` plugin.
- Second macOS gap, found once the socket was out of the way
  (`SSH_AUTH_SOCK= safe-pi --prepare` → `mise ERROR ... Permission denied` on
  `~/.local/share/mise/state`, and `flock: 9: Bad file descriptor`): the image
  creates the user at `/home/<user>` (`useradd --create-home` and the seeded
  mount points under `/home/${USERNAME}`), while the wrapper mounts everything at
  host paths under `HOME=/Users/<user>`. The toolchain volume is mounted at a
  path the image does not have, so Docker gives a new volume no user ownership
  and it is root-owned. On Linux both homes are `/home/<user>`.
- The relay was verified by hand: `ssh -F ~/.colima/ssh_config -N
  -o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes -R <vm>/agent.sock:$SSH_AUTH_SOCK
  -R <vm>/herdr.sock:$HERDR_SOCKET_PATH colima`, then a container of
  `safe-pi:current-u502` with both mounted via `--mount type=bind`: `ssh-add -l`
  listed the host key and a unix connect to the Herdr socket succeeded. The VM
  user is `lima` with uid 502, the host uid, so the `0600` forwarded sockets are
  usable by the sandbox user. With `-f -M -S <own control path>`, the forwards
  are ready in about 0.93 s.
- `~/.colima/ssh_config` points at Lima's persistent master (`ControlMaster auto`,
  `ControlPersist yes`, `ControlPath ~/.colima/_lima/colima/ssh.sock`) and says
  Lima does not use the file itself.
- The keys are chosen per shell: the history shows `eval "$(ssh-agent -s)"` then
  `ssh-add ~/.ssh/id_bjd` or `~/.ssh/id_personal`. The launchd agent
  (`/private/tmp/com.apple.launchd.*/Listeners`) holds no identities.
- Herdr's socket is per session: `HERDR_SOCKET_PATH` was
  `~/.config/herdr/sessions/study/herdr.sock`.
- The wrapper already stays the parent of `docker run` (no `exec`), so it can
  close the relay when the sandbox exits.
- Not this ticket: `git/.gitconfig`'s `credential.helper = !/opt/homebrew/bin/gh
  auth git-credential` does not exist in the sandbox, which is equally true on
  Linux today.
- Workaround until then: `SSH_AUTH_SOCK= safe-pi` starts the sandbox without an
  agent (commits work, SSH push/pull do not).

## Open questions

- Is macOS support worth bringing into scope, or is the outcome a clear refusal
  (`safe-pi` exits with a message on Darwin) plus the documented workaround?
- How does the wrapper know the daemon is in a VM: `uname -s` = `Darwin`, the
  daemon's `docker info`, or a probe? Linux with a remote or rootless daemon has
  the same problem in principle.
- Should the wrapper probe `/run/host-services/ssh-auth.sock` before using it
  (e.g. a throwaway `docker run --mount type=bind,...` that fails cleanly when the
  source is absent), or mount it unconditionally and let the container's
  `ssh-add` fail? A probe costs a container start per run.
- Should every bind switch from `--volume` to `--mount type=bind`, so a missing
  source is an error instead of a directory the daemon creates?
- Does the Herdr reporter need a transport that crosses the VM (e.g. a TCP or
  vsock forward), or is Herdr attribution out of scope on macOS?
- Should Colima's `forwardAgent: true` live in this repository (Colima is not
  managed here today), and should the per-shell `ssh-agent -s` be consolidated
  into one stable agent first?

## Comments

### Decision (2026-10-10)

Settled in a grilling session; recorded in ADR 0008, with the terms Daemon VM
and Socket relay in `CONTEXT.md`.

- **Scope:** macOS with Colima only. Docker Desktop and other daemons on macOS
  are refused; Linux is unchanged.
- **Which agent:** the invoking shell's `$SSH_AUTH_SOCK`, as on Linux. Colima's
  `forwardAgent` is rejected: it pins whichever agent `colima start` saw and does
  nothing for Herdr. Consolidating the per-shell agents is therefore not needed.
- **Transport:** a socket relay per start over the sandbox's own SSH connection
  to the Colima VM, not Lima's persistent master and not a TCP relay.
- **Herdr:** in scope, over the same relay.
- **Detection:** Darwin plus `docker info` naming the Colima profile.
- **Failure:** warn per socket and start without it.
- **Modes:** run and `--shell` relay; `--prepare` does not; `--dry-run` prints.
- **Binds:** all switch to `--mount type=bind`.
- **Home:** the image takes the host's `$HOME` as a build argument and label.
- **Records:** ADR 0008, a one-line pointer in ADR 0002, the README.

### Implementation and verification (2026-10-10)

Built on `feat/safe-pi-macos` and integrated into `main`; `tests/run --full`
ended with `FULL GATE: PASS`.

Verified on this macOS host (arm64, Docker CLI 29.5.2, Colima 0.10.1 `vz`/virtiofs,
Herdr 0.9.3), with the image rebuilt for `HOME=/Users/samuel.santos`:

- **Agent.** With a throwaway key in a fresh `ssh-agent`, `ssh-add -l` in
  `safe-pi --shell` lists the same fingerprint as on the host, and `ssh -v` to
  GitHub from the sandbox offers the agent's key. **Not verified:** a real
  `git push` over SSH — this host's keys are passphrase-protected and none is in
  the keychain, so there was nothing to load non-interactively. Please confirm
  once with a loaded key.
- **Herdr attribution.** In an isolated headless session (`macverify`), the
  sandboxed pane showed `agent: safe-pi`, `display_agent: Pi`, `idle`.
- **Herdr restart.** After `herdr server stop` and a restart, the pane came back
  inside the sandbox in the same conversation (the stored command was
  `safe-pi --session <id>`) and was re-attributed to Pi over a fresh relay. A
  session with no message yet has no file, so `--session` reports "No session
  found" — as on Linux.
- **`--prepare`.** Converged all 21 tools into the toolchain volume (about
  2.5 minutes including the image build); a second run exits 0 in half a second.
- No relay directory or SSH master was left on the host or in the VM after any
  of the runs.

Findings that shaped the build:

- A socket on the shared home cannot be mounted over: the daemon fails with
  `openat2 .../herdr.sock: operation not supported`. The relayed Herdr socket is
  therefore mounted at `/run/safe-pi/herdr.sock` and the reporter's
  `SAFE_PI_HERDR_SOCKET_PATH` points there (named only when the relay is up).
  Recorded in ADR 0008.
- The relay is one master connection plus a `mkdir` and one `-O forward` per
  socket, so a refused forward costs only its own socket.
- A dry run on macOS asks the daemon for its name (`docker info --format`), the
  one thing it needs to pick the host alias; it refuses an unsupported daemon
  like a real run, and assumes `colima` when none is reachable.
- The "table of resources" in the usage guide is the README's "What the sandbox
  sees" list; it names the relay, and a macOS section and two troubleshooting
  rows were added.
- The wrapper test now takes about 12 s on this machine (about 7 s before), over
  the Fast gate's 5 s unit budget, which it already exceeded here.
