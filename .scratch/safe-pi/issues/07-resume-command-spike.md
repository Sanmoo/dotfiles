# 07 — Spike: a sandbox that declares its own resume command

**What to build:** An executable answer to one question: can a sandboxed Pi tell Herdr how to restore itself, so that a restored pane resumes inside the sandbox instead of failing closed to a shell? The shape to test is a container-side integration that reports state, session, and its own resume command under its own source, with the Herdr-managed integration disabled inside the sandbox. The ticket is time-boxed and produces an answer, not a shipped path: if it works, it proposes the follow-up that wires it in; if it does not, the fail-closed decision stands unchanged.

**Blocked by:** 03 — Container contract: mounts and environment

**Status:** ready-for-agent

**Type:** prototype

- [ ] A container-side integration reports state, session, and a resume command under its own source, with the Herdr-managed integration disabled inside the sandbox.
- [ ] A Herdr server restart is exercised, and the observed outcome — conversation resumed inside a sandbox, or pane returned as a shell — is recorded explicitly.
- [ ] The answer states whether Herdr accepts a resume command from a second source on a pane, and what it does with duplicate session references.
- [ ] If the mechanism works, a follow-up ticket is proposed; if it does not, the ADR's fail-closed decision is recorded as still standing.
- [ ] Nothing in the shipped path changes as a result of this ticket.

## Comments
