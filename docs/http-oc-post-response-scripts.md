# `http oc` post-response scripts

`http oc` can run one trusted JavaScript `after-response` script from the selected request document. The request must use the standard OpenCollection shape:

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

## Current scope

- Node.js must be installed and available as `node`.
- Request-level scripts must be `after-response` entries and execute in declaration order. They share temporary runtime variables for this one request execution.
- The script runs after a complete main-request response, including HTTP `4xx` and `5xx` responses. Transport failures, dry runs, and internal OAuth token requests do not invoke it.
- The supported response API is `res.body`, `res.status`, `res.headers`, `res.getBody()`, `res.getStatus()`, `res.getHeaders()`, and `res.getHeader(name)`.
- The supported variable API is `bru.getVar(name)`, `bru.setVar(name, value)`, and `bru.getProcessEnv(name)`. `getVar` starts with the request's resolved variables (using normal `http oc` precedence); `setVar` creates a temporary overlay visible to later scripts, while `getProcessEnv` reads the environment inherited from the calling shell.
- `console.log` and `console.error` both write diagnostics to stderr. The HTTP response remains on stdout, even when the script fails.
- The complete script sequence has one 10-second limit, not a separate limit per script. Exceptions, failures, timeout, and unsupported API use fail with a nonzero status and prevent later scripts from running.

This is a deliberately small Bruno-compatible subset, not full Bruno compatibility. It is **not a secure sandbox for untrusted JavaScript**: run only scripts from collections you trust. Package imports and filesystem/command-execution APIs are not part of the interface.

Collection- and folder-level scripts, other lifecycle stages, collection/Environment setters, test APIs, request chaining, and shell exports are rejected as unsupported rather than partially executed. Runtime variables are discarded after the invocation and never modify collection or Environment documents. `--export` is reserved for a later feature and does not authorize scripts.
