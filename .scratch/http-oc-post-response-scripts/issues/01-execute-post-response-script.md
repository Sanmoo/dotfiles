# 01 — Execute a post-response script with response access

**What to build:** An explicitly authorized `http oc` request can execute one JavaScript post-response script, inspect the received response, and report diagnostics or reject the response without hiding its output. This is useful independently of shell exports: a script can validate an HTTP response and make the command fail when its conditions are not met.

**Blocked by:** None — dependency-ready; implementation still requires the authorization below.

**Status:** ready-for-agent

**Authorization:** Ticket publication only has been authorized. Do not start implementation until the user separately authorizes it. The status indicates specification readiness, not permission to execute work.

**Source:** Approved specification “http oc: post-response scripts and calling-shell exports”. This ticket delivers the first vertical slice, not the complete feature.

- [ ] A request document containing one JavaScript post-response script in the standard OpenCollection `runtime.scripts` shape runs it only when `--allow-scripts` is present. No proprietary language field is introduced.
- [ ] The script runs through Node.js after a complete main-request response. It can read `res.body`, `res.status`, and `res.headers`, plus `res.getBody`, `res.getStatus`, `res.getHeaders`, and `res.getHeader`, within the approved Bruno-compatible subset.
- [ ] Complete `4xx` and `5xx` responses reach the script; the script decides whether their status is acceptable. HTTP error status is not automatically equated with transport failure.
- [ ] `console.log` and `console.error` both write to stderr. HTTP response output remains on stdout, including when the script throws or otherwise fails.
- [ ] Missing script authorization, missing required Node.js, and detectable unsupported script configurations fail clearly before the main request is sent. Collection/folder scripts and unsupported lifecycle stages are not silently inherited or ignored when detected.
- [ ] Script exceptions, unsupported API use, and expiration of the 10-second execution limit return a nonzero exit code. Unsupported APIs must not be successful no-ops.
- [ ] The initial interface does not expose package imports or filesystem/command-execution APIs. Documentation explicitly says this is not a secure sandbox for untrusted JavaScript and is not full Bruno compatibility.
- [ ] Transport failure, dry-run, and internal OAuth requests do not invoke the script. Existing OAuth acquisition before dry-run is not redesigned or described as side-effect-free.
- [ ] Until later tickets deliver them, multiple scripts, runtime-variable APIs, and shell exports are not advertised as supported. Multiple-script configuration or export options fail before sending rather than silently executing a partial feature; unsupported runtime API use fails clearly during script execution.
- [ ] Requests without scripts or export options retain existing behavior, including response-output options and transport exit behavior.
- [ ] Process-boundary tests use temporary collections and fake responses to demonstrate successful response inspection, HTTP-error inspection, script failure, timeout, preflight rejection, stdout/stderr separation, and excluded execution paths. No live APIs or credentials are used.
- [ ] User documentation explains authorization, the currently supported API, prerequisites, output behavior, failure timing, and the scope that subsequent tickets will add.

**Scope boundary:** Response processing only. Sharing runtime variables is ticket 02; calling-shell mutation is ticket 03; multiple atomic exports are ticket 04. Necessary local restructuring and regression tests belong in this slice, not in a separate horizontal prefactoring ticket.
