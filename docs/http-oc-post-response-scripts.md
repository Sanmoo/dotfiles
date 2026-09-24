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
- Exactly one request-level script is supported, and its type must be `after-response`.
- The script runs after a complete main-request response, including HTTP `4xx` and `5xx` responses. Transport failures, dry runs, and internal OAuth token requests do not invoke it.
- The supported response API is `res.body`, `res.status`, `res.headers`, `res.getBody()`, `res.getStatus()`, `res.getHeaders()`, and `res.getHeader(name)`.
- `console.log` and `console.error` both write diagnostics to stderr. The HTTP response remains on stdout, even when the script fails.
- Script execution has a 10-second limit. Exceptions and unsupported API use fail with a nonzero status.

This is a deliberately small Bruno-compatible subset, not full Bruno compatibility. It is **not a secure sandbox for untrusted JavaScript**: run only scripts from collections you trust. Package imports and filesystem/command-execution APIs are not part of the interface.

Collection- and folder-level scripts, other lifecycle stages, multiple scripts, runtime-variable APIs, and shell exports are rejected as unsupported rather than partially executed. `--export` is reserved for a later feature and does not authorize scripts.
