# 03: Split the OC test file into smaller parallel files

**Origin:** `.scratch/quality-gateway/spec.md`, Out of Scope, item 3.

**What to build:** the single OC test file, a linear list of about 2700 scenarios that share progressive fixtures, is divided into smaller files that can run in parallel. The Fast gate bound would drop below 3 s. This is a structural refactor of the suite.

**Blocked by:** 02, conditionally. Only start if the Full gate budget is still exceeded after 02 is done.

**Status:** needs-triage

- [ ] Every scenario from the original file still runs, with its assertions unchanged.
- [ ] Shared fixtures are either duplicated safely or moved into a shared setup, with no ordering dependency between the new files.
- [ ] The test inventory used by the quality gateway acceptance criteria is updated to reflect the new file count.
