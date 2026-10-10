# safe-pi on macOS runs against Colima and relays host sockets over the VM's SSH

ADR 0002 assumed a Docker daemon on the host itself, where the SSH agent and Herdr sockets are bind-mounted by path. On macOS the daemon runs in a Daemon VM, which sees neither: the agent socket under `/var/folders` is outside what the VM shares, and no unix socket crosses the virtiofs share anyway. The decision is to support macOS with Colima only, and to reach the host sockets through a socket relay: for each sandbox start, the wrapper opens its own SSH connection to the Colima VM (the `colima`/`colima-<profile>` alias of the `ssh_config` Colima generates, chosen from the daemon's name) with one remote unix-socket forward per host socket, and mounts the forwarded sockets into the container. The relay follows the invoking shell's `$SSH_AUTH_SOCK`, exactly like the bind mount on Linux, because the key is chosen per shell (`ssh-add ~/.ssh/id_bjd` or `id_personal`). Linux keeps the direct bind mounts.

## Considered Options

- **Colima's `forwardAgent: true`** (Lima links it at `/run/host-services/ssh-auth.sock`, the same path Docker Desktop uses). Rejected: it forwards the agent of the environment `colima start` ran in, fixed until the VM restarts, so the sandbox would sign with an arbitrary key instead of the invoking shell's; it does nothing for Herdr; and it needs a VM restart to enable.
- **A TCP relay** (`socat` on the host exposing the socket on a port the VM reaches). Rejected: any local process that connects to the port can use the agent, and it adds a host dependency.
- **Multiplexing the forwards on Lima's persistent SSH master** (`ssh -O forward`). Rejected despite being nearly free: it relies on a Lima internal (the generated config says Lima does not use it), and a wrapper killed without cleanup leaves the forward in that master until the VM restarts. The sandbox's own connection costs about 0.9 s and dies with the wrapper, so the wrapper opens it alongside its other pre-start checks.
- **Any macOS daemon** (Docker Desktop, OrbStack, plain Lima) or generic Daemon VM detection. Rejected: Colima is the only daemon in use, and the only one this can be verified against. Another daemon on macOS is refused with a message instead of half-working.
- **Refusing macOS altogether.** Rejected: Pi and Herdr are used daily on the macOS host.

## Consequences

- The sandbox user's home is the host's `$HOME` (`/Users/<user>` on macOS), passed to the image build and recorded in a label; an image built for another home is stale and rebuilt. Host path parity requires it, and on Linux it is the `/home/<user>` it always was.
- Binds use `--mount type=bind`, so a source the daemon cannot see fails as a missing source instead of becoming a root-owned directory the daemon creates.
- A relay that cannot be opened is a warning, and the sandbox starts without that socket — the same fail-open policy as a missing agent on Linux and as toolchain convergence.
- `--prepare` opens no relay; `--dry-run` prints the relay command next to the Docker invocation and runs neither.
- The sandbox user's uid matches the Colima VM user's (Lima mirrors the host uid), which is what lets the container use a forwarded socket owned by that user with mode `0600`.
