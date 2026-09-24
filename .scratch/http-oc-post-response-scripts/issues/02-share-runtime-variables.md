# 02 — Share runtime variables between post-response scripts

**What to build:** An authorized request can run multiple post-response scripts in order. One script can extract a response value and another can use it through shared runtime variables, while also reading the request's resolved variables and the inherited shell environment. Nothing is persisted to the collection or Environment.

**Blocked by:** 01 — Execute a post-response script with response access.

**Status:** ready-for-agent

**Authorization:** Ticket publication only has been authorized. Do not start implementation until the user separately authorizes it. The status indicates specification readiness, not permission to execute work.

**Source:** Approved specification “http oc: post-response scripts and calling-shell exports”. This slice extends the response-processing behavior delivered by ticket 01.

- [ ] Multiple supported post-response scripts in the selected request document execute in declaration order and share runtime variables during that execution.
- [ ] `bru.getVar` initially reads the request's resolved variables using the existing `http oc` precedence, rather than substituting a different Bruno-wide precedence model.
- [ ] `bru.setVar` creates or overwrites a temporary overlay visible to subsequent reads and later scripts. Changing a runtime value does not change the already-sent request.
- [ ] `bru.getProcessEnv` reads the environment inherited from the calling shell. Runtime variables, the selected Environment, and shell environment variables remain distinct concepts.
- [ ] Values explicitly assigned through `bru.setVar` during the current execution are distinguishable from values merely inherited through request-variable resolution. Ticket 03 uses this distinction to enforce export eligibility; reading a value alone is not an assignment.
- [ ] Temporary assignments do not persist to collection/Environment files and do not survive into a separate invocation. No shell variables are changed by `bru.setVar` alone.
- [ ] The 10-second limit covers the complete script sequence, not a fresh 10 seconds for each script. Expiration or script failure returns nonzero and preserves the received response output.
- [ ] A failure in a script prevents subsequent scripts from being executed as though the sequence had succeeded.
- [ ] Collection/Environment setters, test APIs, request chaining, and unsupported lifecycle scopes remain unsupported and fail clearly rather than becoming silent no-ops or shell-export operations.
- [ ] Script authorization, response access, stdout/stderr separation, preflight checks, and exclusions for transport failure, dry-run, and internal OAuth remain intact.
- [ ] Shell export options remain unavailable until ticket 03 and cannot silently claim to modify the caller.
- [ ] Process-boundary tests demonstrate extraction in one script and consumption in another, initial variable precedence, temporary overwrite behavior, inherited process-environment reads, failure in a later script, and a single total execution limit.
- [ ] Tests verify that repeated invocations do not share temporary state and that collection/Environment documents remain unchanged. Use temporary collections and fake values, not live APIs or credentials.
- [ ] Documentation describes script ordering, the supported variable APIs, temporary scope, the overall timeout, and the distinction between runtime variables and shell exports.

**Scope boundary:** Ordered scripts and temporary variable sharing only. Selecting and exporting a script-produced value into the calling shell is ticket 03; atomic export sets are ticket 04.
