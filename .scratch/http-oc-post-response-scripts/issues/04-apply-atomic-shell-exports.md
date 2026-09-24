# 04 — Apply multiple shell exports atomically

**What to build:** One direct request invocation can export several script-produced runtime variables into the calling zsh session through repeated `--export` options. A login can provide both a token and an account identifier, with the guarantee that either the complete selected set is applied or the previous shell state is preserved.

**Blocked by:** 03 — Export a runtime variable to the calling zsh session.

**Status:** ready-for-agent

**Authorization:** Ticket publication only has been authorized. Do not start implementation until the user separately authorizes it. The status indicates specification readiness, not permission to execute work.

**Source:** Approved specification “http oc: post-response scripts and calling-shell exports”. This slice completes repeated export selection and set-wide atomicity without weakening the single-export guarantees.

- [ ] Repeated `--export SHELL_NAME=runtime_name` options select multiple mappings for one invocation, replacing ticket 03's explicit single-mapping restriction.
- [ ] Successful processing creates or overwrites every selected destination in the calling zsh session; a subsequent child command sees the complete set.
- [ ] Every mapping independently satisfies the existing source-assignment, string-type, valid-name, literal-transfer, and NUL checks. Empty strings remain valid.
- [ ] Detectable option or destination-name errors fail before sending the request. Errors discovered from script-produced values fail after receiving the response without applying any exports.
- [ ] A missing source, source never assigned in this execution, or invalid value in any mapping prevents all selected destinations from changing, even if earlier mappings are valid.
- [ ] Failure in any post-response script or expiration of the total execution limit applies no exports, including values produced before the failure.
- [ ] Failure to apply any destination must not leave earlier destinations updated. Preserve the prior value and export state of every selected destination and remove no pre-existing variable; destinations that were previously absent remain absent on failure.
- [ ] Unrelated shell variables, other sessions, collection/Environment documents, and startup configuration remain unchanged. The export mechanism still does not run the full collection script in the parent shell.
- [ ] Set validation and application errors return nonzero without disclosing exported values, contaminating stdout with transfer data, or hiding the HTTP response already received.
- [ ] A single mapping retains ticket 03's behavior. Requests without exports and all established lifecycle exclusions remain unchanged.
- [ ] Calling-zsh boundary tests demonstrate successful multiple exports and all-or-none behavior when a later source is missing, invalid, or not assigned by the current scripts.
- [ ] Tests include a destination that cannot be assigned, alongside earlier valid destinations with previously exported, unexported, and absent states, and verify exact preservation after failure. Values containing shell metacharacters remain literal throughout the set operation.
- [ ] Tests cover a later script exception and the sequence timeout with multiple selected values, while confirming response stdout, diagnostic stderr, and nonzero status. Use fake responses and values only.
- [ ] Documentation shows repeated selection and explains that atomicity covers the selected shell exports, not the already-sent HTTP operation or arbitrary script side effects. Direct-shell limitations, trust warnings, and the lack of automatic response/log redaction remain explicit.

**Scope boundary:** Complete export sets only. This does not add variable removal, persistent exports, other shell integrations, extra scripting APIs, collection/folder inheritance, or rollback of HTTP operations.
