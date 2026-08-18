# 04 — macOS real-machine smoke test

**What to build:** A one-time verification on the real macOS machine (this repository's Linux host cannot exercise it): the resolved Microsoft Edge binary opens the federated signin URL in a fresh `aws-<profile>` browser profile, the ECS deep-link lands logged in, and the session survives alongside another account logged in a different browser profile.

**Blocked by:** 02 — Browser profile isolation, 03 — Service deep-links

**Status:** ready-for-human

- [ ] `aws-console --profile <named>` on macOS opens Edge in a dedicated `aws-<profile>` browser profile and the console session is logged in.
- [ ] Logging into a second AWS profile in its own browser profile does not evict the first account's session.
- [ ] `aws-console ecs --profile <named>` lands on the ECS console in the profile's configured region.
- [ ] Bare `aws-console` on macOS keeps opening in the default browser profile, with the existing default-account session intact.
- [ ] The browser override environment variable is honored on macOS when set.

## Comments
