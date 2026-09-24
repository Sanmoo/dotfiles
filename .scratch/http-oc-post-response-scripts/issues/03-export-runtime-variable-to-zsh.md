# 03 — Export a runtime variable to the calling zsh session

**What to build:** After a successful request and post-response script sequence, a direct `http oc` invocation can export one selected runtime variable into the calling zsh session. Subsequent commands in that terminal inherit the value without a per-request manual `eval` or `source` step.

**Blocked by:** 02 — Share runtime variables between post-response scripts.

**Status:** ready-for-agent

**Authorization:** Ticket publication only has been authorized. Do not start implementation until the user separately authorizes it. The status indicates specification readiness, not permission to execute work.

**Source:** Approved specification “http oc: post-response scripts and calling-shell exports”. This slice delivers a complete, safe single-export path before ticket 04 adds multiple mappings.

- [ ] With zsh integration loaded, the normal `http oc` invocation accepts one `--export SHELL_NAME=runtime_name` mapping and makes the selected value available to subsequent child processes of that same shell.
- [ ] `--export` is separate from `--allow-scripts` and does not implicitly authorize JavaScript execution. Missing authorization still prevents a scripted request from being sent.
- [ ] Exporting without the required shell integration fails clearly before sending the request, rather than reporting a child-process change as a successful terminal export.
- [ ] Malformed mapping syntax and invalid destination names fail before sending wherever detectable. More than one mapping is explicitly rejected before sending in this slice; it must not apply just the first or last mapping.
- [ ] The source must have been explicitly assigned through `bru.setVar` during this execution. A missing source or a value only available from resolved request variables fails without changing the shell.
- [ ] Export values must be strings. Empty strings are valid; non-string values and NUL characters fail without implicit conversion. Scripts can explicitly perform their own string conversion.
- [ ] Strings containing whitespace, quotes, newlines, and shell metacharacters arrive unchanged and are treated as literal data, never shell code.
- [ ] A successful export creates or overwrites only the selected destination. No variable-removal operation is introduced.
- [ ] No shell mutation occurs until the entire script sequence succeeds and the export is validated. Exceptions, timeout, invalid values, and failure to apply the export return nonzero and preserve the destination's prior value and export state, including prior absence.
- [ ] The integration applies only the selected value; it does not run the collection's full script inside the interactive shell. Unrelated variables and other shell sessions remain unchanged.
- [ ] Executing a request does not persist export values, rewrite startup files, or edit collection/Environment documents. Document how to load the integration separately from request execution.
- [ ] Export-transfer data does not enter the HTTP response stream. Export handling and its errors do not print values; response stdout and script-diagnostic stderr remain available on post-processing failure.
- [ ] Dry-run, transport failures, and internal OAuth requests never apply an export. Successful HTTP transport alone is insufficient if the post-response script rejects the response.
- [ ] A subsequent request can use the exported variable through existing process-environment interpolation; bare request-variable interpolation does not gain an implicit shell lookup.
- [ ] Calling-zsh boundary tests prove that a subsequent child command observes a new value and a renewed value, and that failure preserves previously exported, unexported, and absent destination states. Merely inspecting a Python child's environment is insufficient.
- [ ] Tests cover empty and hostile-looking literal strings, rejected values, missing integration, multiple-mapping rejection, output separation, and unchanged no-export behavior, using only fake responses and credentials.
- [ ] Documentation states the zsh prerequisite, explicit export selection, lack of persistence, sensitive-output limits, and the direct-invocation guarantee. Pipelines, command substitutions, and subshells are not promised to modify their outer shell. Bash/fish and safe execution of untrusted JavaScript are not claimed.

**Scope boundary:** Exactly one selected shell export. Ticket 04 removes the single-mapping restriction and extends the same validation and failure guarantees to complete export sets. Do not defer literal-value safety or single-destination failure preservation to that ticket.
