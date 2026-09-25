# `http oc` post-response scripts

`http oc` can run one or more trusted JavaScript `after-response` scripts from the selected request document. The request must use the standard OpenCollection shape:

```yaml
runtime:
  scripts:
    - type: after-response
      code: |-
        if (res.getStatus() !== 200) {
          throw new Error("unexpected response status");
        }
        console.log(res.getHeader("content-type"));
```

Authorize execution explicitly with `--allow-scripts`:

```sh
http oc --no-interactive -c Example --allow-scripts Login
```

## Calling-shell exports

A direct invocation can export explicitly selected runtime variables into the
calling zsh session. Repeat `--export` for each mapping:

```sh
source ~/.http-oc.zsh
http oc --no-interactive -c Example --allow-scripts \
  --export TOKEN=runtimeToken --export ACCOUNT=runtimeAccount Login
```

The integration is a zsh prerequisite and is intentionally loaded separately
from request execution. It applies only to a direct command; pipelines, command
substitutions, and subshells are not promised to modify their outer shell. Each
mapping is a `SHELL_NAME=runtime_name` pair; repeat `--export` to select multiple
values. The complete selected set is applied atomically: if any source is invalid,
any script fails, or the shell cannot apply a destination, no selected destination
changes. Each source must have been assigned with `bru.setVar` during this execution
and must be a string; empty strings are valid, but NULs and other types are rejected.
Values are transferred as literal data rather than shell code, and exports are only
applied after all post-response scripts succeed. Atomicity covers the selected shell
exports, not the already-sent HTTP operation or arbitrary script side effects. A
failed request, script, or validation leaves all selected destinations unchanged.
Exports are temporary shell state:
request execution does not persist them or rewrite startup, collection, or
Environment documents. Only the selected destination is changed, and export
values are not printed or included in the HTTP response stream. Do not use this
feature for untrusted JavaScript; the script runner is not a security sandbox.

Load the integration explicitly (for example, `source ~/.http-oc.zsh`) after
installing this dotfiles package. Bash and fish are not supported by this
integration.

## Current scope

- Node.js must be installed and available as `node`.
- Request-level scripts must be `after-response` entries and execute in declaration order. They share temporary runtime variables for this one request execution.
- The script runs after a complete main-request response, including HTTP `4xx` and `5xx` responses. Transport failures, dry runs, and internal OAuth token requests do not invoke it.
- The supported response API is `res.body`, `res.status`, `res.headers`, `res.getBody()`, `res.getStatus()`, `res.getHeaders()`, and `res.getHeader(name)`.
- The supported variable API is `bru.getVar(name)`, `bru.setVar(name, value)`, and `bru.getProcessEnv(name)`. `getVar` starts with the request's resolved variables (using normal `http oc` precedence); `setVar` creates a temporary overlay visible to later scripts, while `getProcessEnv` reads the environment inherited from the calling shell.
- `console.log` and `console.error` both write diagnostics to stderr. The HTTP response remains on stdout, even when the script fails.
- The complete script sequence has one 10-second limit, not a separate limit per script. Exceptions, failures, timeout, and unsupported API use fail with a nonzero status and prevent later scripts from running.

This is a deliberately small Bruno-compatible subset, not full Bruno compatibility. It is **not a secure sandbox for untrusted JavaScript**: run only scripts from collections you trust. Package imports and filesystem/command-execution APIs are not part of the interface.

Collection- and folder-level scripts, other lifecycle stages, collection/Environment setters, test APIs, and request chaining are rejected as unsupported rather than partially executed. Runtime variables are discarded after the invocation and never modify collection or Environment documents. `--export` is separate from `--allow-scripts` and does not authorize scripts.
