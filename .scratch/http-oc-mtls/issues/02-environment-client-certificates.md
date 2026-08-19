# 02 — Client certificates per environment with precedence

**What to build:** client certificates declared under `config.environments[].clientCertificates` participate in the same domain-matched selection as the collection manifest's `config.clientCertificates`. The two lists are merged with the environment winning per `domain` — the same precedence direction variables use. Environment entries can reference the selected environment's own variables, and a collection certificate still applies when the environment defines no entry for that domain.

**Blocked by:** 01 — Manifest client certificates reach the main request.

**Status:** ready-for-agent

- [ ] A certificate declared only in the environment is matched and presented when that environment is selected
- [ ] For the same `domain` in both lists, the environment entry wins when that environment is selected
- [ ] A collection-level certificate still applies when the selected environment defines no entry for its `domain`
- [ ] Environment entries resolve variables from the full resolved context (collection, request, environment, CLI), including the environment's own variables
- [ ] A `disabled` environment entry is skipped and does not mask the collection entry for the same domain
- [ ] The merged selection is covered at the process boundary: dry-run shows the environment certificate when it wins and the collection certificate when it is the only match
