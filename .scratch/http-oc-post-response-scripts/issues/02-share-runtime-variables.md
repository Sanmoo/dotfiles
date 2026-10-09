# 02 — Share runtime variables between post-response scripts

**What to build:** An authorized request can run multiple post-response scripts in order. One script can extract a response value and another can use it through shared runtime variables, while also reading the request's resolved variables and the inherited shell environment. Nothing is persisted to the collection or Environment.

**Blocked by:** 01 — Execute a post-response script with response access.

**Status:** resolved

**Authorization:** Granted — implementation has landed; see Comments.

**Source:** Approved specification “http oc: post-response scripts and calling-shell exports”. This slice extends the response-processing behavior delivered by ticket 01.

- [x] Multiple supported post-response scripts in the selected request document execute in declaration order and share runtime variables during that execution.
- [x] `bru.getVar` initially reads the request's resolved variables using the existing `http oc` precedence, rather than substituting a different Bruno-wide precedence model.
- [x] `bru.setVar` creates or overwrites a temporary overlay visible to subsequent reads and later scripts. Changing a runtime value does not change the already-sent request.
- [x] `bru.getProcessEnv` reads the environment inherited from the calling shell. Runtime variables, the selected Environment, and shell environment variables remain distinct concepts.
- [x] Values explicitly assigned through `bru.setVar` during the current execution are distinguishable from values merely inherited through request-variable resolution. Ticket 03 uses this distinction to enforce export eligibility; reading a value alone is not an assignment.
- [x] Temporary assignments do not persist to collection/Environment files and do not survive into a separate invocation. No shell variables are changed by `bru.setVar` alone.
- [x] The 10-second limit covers the complete script sequence, not a fresh 10 seconds for each script. Expiration or script failure returns nonzero and preserves the received response output.
- [x] A failure in a script prevents subsequent scripts from being executed as though the sequence had succeeded.
- [x] Collection/Environment setters, test APIs, request chaining, and unsupported lifecycle scopes remain unsupported and fail clearly rather than becoming silent no-ops or shell-export operations.
- [x] Script authorization, response access, stdout/stderr separation, preflight checks, and exclusions for transport failure, dry-run, and internal OAuth remain intact.
- [x] Shell export options remain unavailable until ticket 03 and cannot silently claim to modify the caller.
- [x] Process-boundary tests demonstrate extraction in one script and consumption in another, initial variable precedence, temporary overwrite behavior, inherited process-environment reads, failure in a later script, and a single total execution limit.
- [x] Tests verify that repeated invocations do not share temporary state and that collection/Environment documents remain unchanged. Use temporary collections and fake values, not live APIs or credentials.
- [x] Documentation describes script ordering, the supported variable APIs, temporary scope, the overall timeout, and the distinction between runtime variables and shell exports.

**Scope boundary:** Ordered scripts and temporary variable sharing only. Selecting and exporting a script-produced value into the calling shell is ticket 03; atomic export sets are ticket 04.

## Comments

Implemented in `general/bin/http` (commit 17d7fb5, "share runtime variables between
scripts"). The test file covers ordered scripts sharing `bru.setVar` values,
`bru.getVar` request-variable precedence, `bru.getProcessEnv`, temporary scope
across invocations, the single sequence-wide limit, and a later-script failure
stopping the rest.
