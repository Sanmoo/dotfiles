# 16 — `safe-pi` cannot start on macOS, where the Docker daemon runs in a VM

**What to build:** `safe-pi` must start on the macOS host (Homebrew `docker` CLI
against Colima) with the same contract it has on Linux, or with an explicitly
documented subset of it. Today the container never starts: the wrapper
bind-mounts the host's SSH agent socket, and the daemon cannot see it.

This is a scope change. The spec lists "macOS support (`pi-mac`)" under *Out of
Scope*; resolving this ticket brings it in, and the README and ADR 0002 are the
living record that has to say so.

**Status:** needs-triage

- [ ] `safe-pi` starts on the macOS host, and a missing or unreachable SSH agent
      degrades to a warning instead of a failed `docker run`.
- [ ] When the VM provides a forwarded agent, `ssh-add -l` inside the sandbox
      lists the host's keys, and `git push` over SSH works from the sandbox.
- [ ] No bind mount the wrapper emits can make the daemon create a missing source
      path (no stray directories left in the VM).
- [ ] The Herdr behaviour on macOS is decided and either working or documented as
      unavailable.
- [ ] The wrapper boundary test covers the macOS branch; the usage guide names
      what the macOS host needs (e.g. Colima's agent forwarding) and what it lacks.

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
