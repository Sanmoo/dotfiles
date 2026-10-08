# 03: Make the external skills installation test hermetic

**Origin:** `.scratch/quality-gateway/spec.md`, §8.3 and out-of-scope item 1.

**What to build:** the external skills installation test passes on any machine. Today it applies the live `agents` package, which contains machine-local skill symlinks, and Stow aborts on those. The apply steps run against a fixture checkout that contains only tracked content. The product defect itself is deferred to its own follow-up.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The apply steps run against a fixture whose `agents` package contains only repository-tracked content.
- [ ] The final assertion still checks the live checkout: only `jira-issue-formatting` is a real directory under the skills folder.
- [ ] The test passes in a clean checkout and in this checkout, where machine-local skill symlinks exist.
