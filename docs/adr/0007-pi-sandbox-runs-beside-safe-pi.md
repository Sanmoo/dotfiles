# pi-sandbox runs beside safe-pi on Docker Sandboxes instead of replacing it

Status: deferred. The work is parked; nothing here is implemented, and `sbx` is not installed. The analysis below stays as the record of what was found.

ADR 0002 kept Pi on plain Docker and rejected Docker Sandboxes, accepting that the sandbox is "a filesystem boundary, not a credential boundary". That decision stays in force for `safe-pi`. The new runtime, `pi-sandbox`, is built on `sbx` (Docker Sandboxes), where each sandbox is a microVM with network denied by default and credentials injected by a host-side proxy, so the agent holds no credential it can read or use. The two coexist: `safe-pi` is unchanged, and `pi-sandbox` replaces it only once it covers the use cases `safe-pi` serves today (Herdr state and session restore, the declared toolchain, the host's Pi configuration, and session continuity with the host).

Herdr is outside the first cut of `pi-sandbox`. The microVM does not reach the host's Unix socket by default, so the reporter that `safe-pi` relies on has no path there yet.

The credential scope is the one in `CONTEXT.md`: no credential the agent can read or use, which covers provider keys and OAuth tokens, the SSH agent (its forwarding is disabled, because signing from inside is a use), the forge token, and secret variables. Provider credentials are proxy-managed; push and other authenticated operations stay on the host.

The backend choice (`sbx`) is conditional on a spike that has not yet run. `sbx` documents Ubuntu 24.04 and later, and Rocky Linux 8, and this host runs Arch Linux, which is not on that list. The install needs root and a Docker account sign-in (`sbx login`). The spike decides whether the backend stays; if it does not, this ADR is revisited.

## Considered Options

- **Replace `safe-pi` with the `sbx` implementation now.** Rejected: `pi-sandbox` does not yet cover Herdr integration, session restore, or the declared toolchain, so replacing `safe-pi` would leave no working sandbox until the gap closes.
- **Harden `safe-pi` on plain Docker** (`--network none`, a custom egress proxy, custom credential injection). Rejected: the proxy and the egress policy would be security components written and maintained here, while `sbx` already provides both.
- **Herdr in the first cut of `pi-sandbox`.** Rejected: it would require exposing the host's Unix socket to a microVM, which the first cut should not depend on.

## Consequences

- The term "sandbox" in `CONTEXT.md` names `safe-pi`'s container. Proposed, not yet decided: call the `pi-sandbox` unit a "microVM sandbox" to keep the two apart.
- `pi-sandbox` depends on a Docker account (`sbx login`), a dependency `safe-pi` does not have.
- The AUR package `docker-sbx-bin` is community-maintained, not Docker's. Installing a root-level daemon from it is a trust decision separate from this ADR.
