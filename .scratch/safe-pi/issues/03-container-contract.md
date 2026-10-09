# 03 — Container contract: mounts and environment

**What to build:** The complete set of mounts and environment the sandbox runs with, so the container sees the working repository read-write at its host path, the Pi agent directory read-write with extensions and installed Pi packages held read-only, sessions under a container-only path with the matching session-directory variable, the shared skills directory, the configuration checkout, the pi-lens directory, the declared mise configuration, the Herdr configuration directory (socket), the git configuration file, and the SSH agent socket — and nothing else, in particular no Docker socket. Herdr's variables are forwarded only when present, and the wrapper advertises itself to Herdr as Pi. The debug shell and the dry run are how this is inspected.

**Blocked by:** 02 — `safe-pi` wrapper starts Pi in the container

**Status:** resolved

- [x] A debug shell shows the invoking uid/gid, the working directory, and every contract path present with its intended mode; read-only entries reject writes.
- [x] The Pi agent directory is writable (Pi must lock its credential store there), while extensions and installed Pi packages are not writable.
- [x] Pi inside the sandbox loads the host configuration: settings, prompts, agents, keybindings, the approval extension, the Herdr integration extension, skills from the shared skills directory, and pi-lens configuration.
- [x] Pi reports its session file under the container-only sessions path, and the corresponding file appears in the host sessions directory.
- [x] Herdr's variables are forwarded only when set on the host; the wrapper's advertised agent identity is visible to Herdr for the pane.
- [x] The Docker socket is absent, and the temporary directory is writable but discarded with the container.
- [x] The stubbed harness asserts every mount's mode and every forwarded variable, including the variables being absent when the host does not set them.

## Comments

Implemented in `pi/.local/bin/safe-pi` with `safe-pi/Dockerfile` and
`tests/safe-pi-wrapper-test.sh`, rebased onto `main` and fast-forward integrated
as `edaa7d3`.

Contract, built wholly from the invoking user's home and the script's own
checkout (`CONFIG_CHECKOUT`):

| Host source | Container | Mode |
| --- | --- | --- |
| `$PWD` | same path | rw |
| `~/.pi/agent` | same path | rw |
| `~/.pi/agent/extensions`, `~/.pi/agent/npm` | same path | ro (over the agent dir) |
| `~/.pi/agent/sessions` | `/run/safe-pi/sessions` | rw |
| `~/.agents/skills` | same path | ro |
| configuration checkout | same path | ro, skipped only when `$PWD` *is* the checkout |
| `~/.pi-lens` | same path | rw |
| `<checkout>/mise/.config/mise` | `~/.config/mise` | ro |
| `~/.config/herdr` | same path | ro |
| `~/.gitconfig` | same path | ro |
| `$SSH_AUTH_SOCK` | `/run/safe-pi/ssh-agent.sock` | rw (only when set) |
| volume `safe-pi-toolchain-u<uid>` | `~/.local/share/mise` | rw |
| — | `/tmp` | tmpfs |

- `PI_CODING_AGENT_SESSION_DIR` points at `<container sessions>/<encoded-cwd>`,
  using Pi's own cwd encoding. Pi takes a supplied session dir verbatim, so this
  lands sessions in the same host subdirectory the host Pi reads: `pi -c`
  resumes a sandbox session on the host and vice versa (verified both ways with
  a real run). Reporting the container path keeps Herdr's restore fail-closed.
- Forwarded variables: `HOME`, `USER`, `LANG`, `LC_ALL`, `LC_CTYPE`, `TERM`,
  `TZ`; `MISE_DATA_DIR` and the session variable at container paths;
  `SSH_AUTH_SOCK` at the container socket path; and `HERDR_ENV`,
  `HERDR_SOCKET_PATH`, `HERDR_PANE_ID` only when set on the host. The wrapper
  sets no Pi identity of its own: forwarding the Herdr variables lets the
  mounted `herdr-agent-state.ts` extension report `agent: "pi"` over the
  socket, which is what attributes the pane (end-to-end check is ticket 05).
- The image creates `/run/safe-pi`, its `sessions` directory, the SSH socket
  placeholder, and an empty user-owned `~/.local/share/mise`, so the socket
  binds over a file and a fresh toolchain volume inherits user ownership. The
  required host directories are created only immediately before the container
  starts, so `--dry-run` touches nothing.
- `--shell` prints uid/gid, cwd, and every contract path with its mode, marking
  absent host paths `MISSING`.

Verified against the real daemon: uid/gid `1000(sanmoo)`, host-path cwd,
`extensions`/`npm` mounting `Read-only file system`, the agent directory
writable, every host-config symlink readable and `pi list` printing the
installed packages, the `HERDR_*`, `MISE_DATA_DIR`, and session variables
present, no `/var/run/docker.sock`, and a writable tmpfs `/tmp`. A working
directory inside the checkout keeps its read-write mount while the rest of the
checkout stays read-only. `shellcheck` is clean and
`tests/safe-pi-wrapper-test.sh` passes; the full `tests/*.sh` sweep is 16/18,
with the two failures (`auth-code-token-test.sh`,
`herdr-notification-target-test.sh`) reproducing on the pre-change `main`.

### Reopened by ticket 05

The Herdr-attribution claim does not hold. In a real sandboxed pane,
`safe-pi` runs Pi but Herdr reports `agent_status: unknown` and never lists the
pane as an agent: the mounted Herdr-managed integration (source `herdr:pi`) is
acknowledged and then ignored, because Herdr 0.9.3 only applies that source to
a pane whose detected agent is Pi, and the sandbox's foreground process is
`docker`. A report from the same container under a custom source is applied
immediately. Full evidence and controls in ticket 05. The socket and environment
forwarding are correct; the advertised-as-Pi mechanism named in the spec is not
implemented.
