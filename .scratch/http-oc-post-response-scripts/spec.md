# http oc: post-response scripts and calling-shell exports

Status: implemented (tickets 01–04 resolved; commits a3f7bd3 run post-response scripts, 17d7fb5 share runtime variables, 8ed994f export to zsh, 0caa977 atomic exports; covered by tests/http-oc-post-response-scripts-test.sh)
Design: approved
Implementation authorization: granted for tickets 01–04 (recorded as satisfied in commit 331c59b, after the implementation landed)

The user approved the behavioral contract below, then explicitly authorized only its recording. This document is not permission to implement, install shell integration, change configuration, or execute collection scripts. The triage gate is for a maintainer to authorize future implementation, not to reopen the agreed design.

## Problem Statement

A request can return a value, such as an access token, that the user needs in subsequent commands in the same terminal. Today, `http oc` neither runs post-response scripts nor exports values into the calling shell.

The existing execution boundary is calling shell → Python `http` → `curl`. An `export` in Python's child process cannot change the calling shell. The feature therefore needs both programmable response processing and explicit cooperation from the calling shell; running the entire script inside the interactive shell is not the solution.

An **Environment** remains the named collection configuration selected with `-e`. It is not the calling shell's environment. Neither collection nor Environment files are modified by this feature.

## Solution

Support OpenCollection's JavaScript `runtime.scripts` entries of type `after-response` in a request document, with an explicitly bounded subset of Bruno's API. Scripts produce runtime variables. Repeated `--export SHELL_NAME=runtime_name` options select which script-produced values become exported variables in the calling zsh session.

The normal invocation remains `http oc …`; once the zsh integration is loaded, the user does not need to run `eval` or `source` for each request.

### Example

Fragment within a login request document:

```yaml
runtime:
  scripts:
    - type: after-response
      code: |-
        if (res.status !== 200) {
          throw new Error("Login failed");
        }
        bru.setVar("token", res.body.access_token);
```

Direct invocation in an integrated zsh session:

```sh
http oc Login -c Example --allow-scripts --export TOKEN=token
```

On success, later commands launched from that same shell inherit `TOKEN`. A later request can use `{{process.env.TOKEN}}`. This does not change bare `{{TOKEN}}` lookup into an automatic shell-environment lookup.

## Approved Behavioral Contract

### 1. Scope and authorization

- Only `after-response` scripts in the selected request document are executable in this version.
- Use the existing OpenCollection YAML shape: `runtime.scripts`, each entry containing `type` and `code`. JavaScript is the supported language; do not add a proprietary language field.
- Scripts run in declaration order and share runtime variables for this execution.
- Script execution requires explicit `--allow-scripts` authorization for the invocation. This is not a security sandbox or a declaration that the collection is safe.
- Finding a script without authorization causes a clear failure before sending the request; do not silently skip it.
- Unsupported lifecycle types and script configurations outside the supported scope, including collection/folder scripts when detected, must be identified rather than silently treated as supported or inherited.
- Unsupported configuration detectable before execution fails before sending the request.
- Requests without scripts or export options retain their existing behavior.

### 2. Runtime and supported API

- Node.js is required to execute scripts. Its availability is checked before sending a request that requires script execution.
- The complete script sequence for one request has a 10-second execution limit, not a separate 10 seconds per script.
- Do not expose package imports or filesystem/command-execution APIs in the initial scripting interface.
- These restrictions must not be advertised as safe isolation for untrusted JavaScript.
- The supported response interface is:
  - `res.body` and `res.getBody()`;
  - `res.status` and `res.getStatus()`;
  - `res.headers`, `res.getHeaders()`, and `res.getHeader(name)`.
- The supported variable interface is `bru.getVar`, `bru.setVar`, and `bru.getProcessEnv`.
- `console.log` and `console.error` are available for diagnostics and both write to stderr.
- Unsupported API use fails clearly; it is not a successful no-op.
- Do not claim full Bruno runtime compatibility. OpenCollection defines the YAML container, while the response and variable APIs above are a specified Bruno-compatible subset.

### 3. Runtime variables

- `bru.getVar` initially sees the variables already resolved for the request, preserving the current `http oc` precedence.
- `bru.setVar` creates or overwrites a temporary overlay, visible to subsequent reads and later scripts in the same execution.
- This overlay is discarded after the execution. It does not persist collection or Environment values, and does not itself export anything to the shell.
- `bru.getProcessEnv` reads the process environment inherited from the calling shell.
- Only a variable explicitly assigned through `bru.setVar` during this execution is eligible for export. Merely finding a value in the resolved request variables is insufficient, even when it has the requested name.
- Do not reinterpret `bru.setEnvVar` or collection setters as shell-export operations. These setters are outside the supported subset.

### 4. Export selection and validation

- `--export SHELL_NAME=runtime_name` is repeatable and is separate from `--allow-scripts`; it is not implicit permission to run code.
- Each mapping selects a runtime variable as the source and an exported shell variable as the destination.
- Export values must be JavaScript strings. There is no implicit conversion of numbers, booleans, objects, lists, `null`, or `undefined`.
- Scripts may explicitly use `String(...)` or `JSON.stringify(...)` when conversion is intended.
- An empty string is valid and means an exported variable with an empty value, not removal.
- A missing source, a source not explicitly assigned in this execution, an incompatible type, an invalid destination name, or a NUL character causes failure without applying any exports.
- Exporting creates or overwrites the explicitly selected destinations. Removing shell variables is out of scope.
- Values must remain literal data when transferred into the shell, including quotes, whitespace, newlines, and shell metacharacters; the export path must not execute their contents.
- Apply the complete export set or none of it. A script failure, timeout, export-validation failure, or failure to apply the set must not leave a partially updated shell environment.
- Preserve previous values and export state on failure, including destinations that were previously absent.

### 5. Calling-shell integration

- Support zsh initially. Bash and fish are not part of this version.
- The integration cooperates with the executable to apply only the selected exports; it does not execute the full collection script inside the interactive shell.
- When exports are requested but the integration is unavailable, report a clear failure before sending the request. Do not claim that a child-process environment change modified the terminal.
- Exporting changes only the calling shell session. Do not modify startup files, persist variable values, or change other terminal sessions.
- The parent-shell guarantee applies to direct invocation in the integrated shell. Pipelines, command substitutions such as `$(…)`, and subshells are not guaranteed to modify the outer shell; document this boundary explicitly.
- The exact installation and child-to-shell handoff mechanisms remain implementation choices, constrained by literal-value transfer, atomic application, and output separation.

### 6. Response lifecycle and failure behavior

- Run scripts after any complete HTTP response, including `4xx` and `5xx` responses. The script decides whether a status is acceptable; the example explicitly rejects non-200 responses.
- Do not run scripts after transport failure, on `--dry-run`, or for internal OAuth requests.
- Dry-run must not execute scripts or apply exports. This feature does not promise to remove the existing OAuth token-acquisition behavior that currently precedes the dry-run branch.
- Validate authorization, unsupported configuration, export-option shape/destination names, shell integration, and runtime prerequisites before sending the request wherever applicable and detectable.
- Failures that can only be discovered while processing the response occur after the request was sent. They return a nonzero exit code, apply no exports, and preserve the received response output.
- The request cannot be undone. Atomicity covers the selected shell exports, not the HTTP operation or arbitrary script side effects.
- Preserve the existing distinction between HTTP error status and transport/process failure; this feature does not introduce an automatic HTTP-status failure policy.

### 7. Output and sensitive values

- Keep the HTTP response on stdout and script diagnostics on stderr.
- Do not mix export-transfer data into the response stream.
- A post-processing failure must not hide a response already received.
- Export handling must not print exported values in logs or confirmation messages. Errors should identify the relevant variable or failure without disclosing its value.
- This is not automatic redaction of HTTP response bodies or user-authored script messages: a response containing a token, or a script explicitly logging one, can still disclose it. No general redaction feature was approved.

## Acceptance Criteria for Future Implementation

These are future validation requirements, not tests run as part of recording this specification.

1. In a controlled zsh session with integration loaded, a login script sets a runtime token and a direct invocation exports it. A subsequent child process of that same shell observes the value.
2. A second successful invocation overwrites an existing exported token; unrelated variables and other sessions are unchanged.
3. Multiple scripts run in declared order, share values through `getVar/setVar`, and multiple `--export` options apply their complete set.
4. Initial `getVar` reads preserve existing request-variable resolution; `setVar` overlays it without changing collection/Environment files.
5. Selecting an inherited/request-resolved value that was never assigned via `setVar` fails without exporting it.
6. Empty strings export successfully. Missing values, incompatible types, invalid destination names, and NUL values fail without any partial update.
7. Strings containing spaces, quotes, newlines, or shell metacharacters arrive unchanged and do not execute shell code.
8. An exception in a later script or expiration of the overall 10-second limit leaves all prior shell values/export states unchanged and returns nonzero.
9. Export application failure does not leave an earlier destination updated.
10. Complete error HTTP responses reach the script; the script can reject them. Transport failures, dry-run, and internal OAuth responses do not invoke the post-response scripts.
11. Missing script authorization, missing required Node.js, missing required shell integration, malformed export options, and detectable unsupported script configurations fail before the main request is sent.
12. Unsupported scripting APIs produce clear failures rather than silent success.
13. stdout remains the response stream, script logs go to stderr, and exports do not contaminate either stream with their values. Response output remains available on post-processing failure.
14. Requests without this feature retain their existing execution and output behavior.
15. Documentation states the direct-shell limitation, trust requirement, bounded API, and lack of collection/Environment persistence.

Use the existing temporary-HOME/collection and stub-curl process harness as a starting point. Add a calling-zsh boundary test for shell mutations; a Python subprocess test alone cannot prove that the caller's environment changed. Use fake responses and values, not live credentials or real API calls.

## Implementation Anchors and Deferred Engineering Details

The following are current-code observations and guidance, not implemented work:

- `general/bin/http`: `make_oc_parser`, `main_oc`, request-variable resolution, and the curl boundary. The main request currently inherits stdout/stderr and returns curl's exit code rather than providing a structured response to a script runtime.
- `zsh/.zshrc`: current HTTP aliases; no existing `http` export wrapper was found during investigation.
- `tests/http-oc-test.sh`: process-level fixtures and stub-curl harness; no existing calling-shell mutation coverage was found.
- `CONTEXT.md`: vocabulary for collection, request document, Environment, post-response script, runtime variable, and shell export.

Runtime packaging, response-capture internals, wrapper installation, and the export handoff protocol are intentionally not selected here. Implementation must preserve the approved contract and surface any newly necessary behavioral decisions rather than silently broadening the API. Do not infer a full Bruno version/conformance target from the small supported subset.

## Out of Scope

- Implementation in this documentation-only task; further explicit authorization is required.
- The Go `httpoc` rewrite or changes to the non-`oc` REST client.
- Bash/fish integration and mutation of outer shells from pipelines/subshells.
- Running the collection script directly in the interactive shell.
- Persistent exports, edits to collection/Environment files, and shell-variable removal.
- A proprietary `http.exportEnv` scripting API or repurposing Bruno variable setters as shell exports.
- Collection/folder script inheritance and lifecycle stages other than request-level `after-response`.
- Full Bruno API support, test APIs, request chaining, package imports, and exposed filesystem/command APIs.
- A secure sandbox for untrusted JavaScript, or general response/log secret redaction.
- Redesigning OAuth or guaranteeing that the pre-existing dry-run path makes no authentication calls.

## Sources and Compatibility Boundaries

- [OpenCollection schema, pinned revision](https://github.com/opencollection-dev/opencollection/blob/535a5c5803da7a3fe1d575fff23350b4a7c43c6a/packages/oc-schema/src/opencollection.schema.json): script container with `type` and `code`, including `after-response`.
- [Bruno OpenCollection YAML reference](https://docs.usebruno.com/opencollection-yaml/structure-reference): JavaScript post-response example using `bru.setVar` and `res.body`.
- [Bruno JavaScript API reference](https://docs.usebruno.com/scripting/javascript-reference.md): response access, runtime variables, and process-environment reads.
- [Older Bruno API reference](https://docs.usebruno.com/v2/testing/script/javascript-reference): Environment persistence differs from current documentation; this is a reason not to promise general setter compatibility.

The YAML format does not by itself specify portable runtime APIs or exports to a calling shell. Explicit runtime-variable-to-shell export selection is an `http oc` contract, not a redefinition of `bru.setVar` or `bru.setEnvVar`.
