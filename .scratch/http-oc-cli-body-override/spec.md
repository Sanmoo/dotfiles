# http oc: CLI body override

Status: ready-for-agent

## Problem Statement

The `http oc` subcommand only knows how to send the body declared in a request document's `request.body` block. To fire a request with a different payload — a one-off JSON blob, a payload read from a file, a value you want to try before committing it to the collection — you have to edit the request document. There is no way to supply the body from the command line.

## Solution

Add `-d`/`--data` (inline body) and `-f`/`--file` (body from a file) flags to the `http oc` subcommand, mirroring the existing REST client's flags. When either is present, it replaces the manifest's `request.body` for that run. Content-Type is derived by a fixed precedence so the common cases need no extra flags, and the "Comando equivalente" printed in interactive mode includes the override so the run is reproducible.

## User Stories

1. As a developer, I want to pass an inline JSON body with `-d`, so that I can POST without editing the request document.
2. As a developer, I want to pass a body from a file with `-f`, so that I can send large or multi-line payloads without shell-quoting pain.
3. As a developer, I want the CLI body to override the manifest's `request.body`, so that I can test a different payload for the same request.
4. As a developer, I want `{{var}}` in the CLI body to resolve against collection, environment, and CLI variables, so that I can parameterize ad-hoc bodies.
5. As a developer, I want an undefined variable in my CLI body to fail with exit 2 and name the variable, so that I catch typos before sending a broken payload.
6. As a developer, I want `-d` on a request whose manifest declares `body.type: json` to keep `Content-Type: application/json`, so that I don't have to re-type the header.
7. As a developer, I want `-f payload.xml` to set `Content-Type: application/xml` even when the manifest declares a JSON body, so that the file extension wins.
8. As a developer, I want `-d` on a request with no manifest body to default `Content-Type: application/json`, so that the common case works with no extra flags.
9. As a developer, I want an explicit `-H "Content-Type: ..."` to always win over any derived type, so that I have the final say.
10. As a developer, I want `-d`/`-f` on a `form-urlencoded` request to be sent verbatim (not re-encoded), so that I control the exact bytes.
11. As a developer, I want `-d` and `-f` used together to fail with exit 2, so that the ambiguity is caught immediately.
12. As a developer, I want `-f` pointing at a missing file to fail with a `file not found` message and exit 2, so that I don't send `@/nonexistent`.
13. As a developer, I want `-f file.jsonc` to have comments stripped before sending, so that I can keep comments in my payload files.
14. As a developer, I want `-d ""` to send an empty body, so that I can POST with no content.
15. As a developer, I want the dry-run (`-n`) to show the `curl` line including my overridden body, so that I can verify before sending.
16. As an interactive user, I want the "Comando equivalente" to include my `-d`/`-f`, so that I can reproduce the exact call later.
17. As a developer, I want requests without `-d`/`-f` to keep their manifest body unchanged, so that existing behavior is not affected.
18. As a developer, I want `-f` file contents to be templated with variables, so that file bodies also benefit from `{{var}}`.
19. As a developer, I want the body override to replace only the body and never the HTTP method, so that a PUT or PATCH keeps its method.
20. As a developer, I want the body override to work in non-interactive mode with `-n`, so that it is scriptable.
21. As a developer, I want the manifest body's variables to be exempt from the missing-variable preflight once I override the body, so that I can override a body without providing variables only the manifest body needed.

## Implementation Decisions

- The `oc` subcommand parser gains `-d`/`--data` and `-f`/`--file`, mirroring the REST client's flag names.
- The body override **replaces** the manifest's `request.body` (override semantics, not "supply only when absent").
- `{{var}}` templating is applied to the CLI body using the existing variable precedence (CLI `-v` > environment > request > collection).
- **Content-Type precedence** (see ADR-0001): explicit `Content-Type` header (CLI `-H` **or** a manifest-declared header) > `-f` file extension (`.json`/`.jsonc` → `application/json`, `.xml` → `application/xml`, otherwise `application/octet-stream`) > manifest `body.type` (applies to `-d` only) > default `application/json`.
- A `form-urlencoded` body supplied via `-d`/`-f` is used **verbatim** — the field list is not reconstructed or re-encoded.
- `-d` and `-f` together are mutually exclusive (exit 2, same message as the REST client).
- `-f` with a missing file fails with exit 2.
- `-f` with a `.jsonc` file strips `//` and `/* */` comments before templating and sending.
- `-d ""` is a valid empty body, distinct from "no body".
- The "Comando equivalente" builder includes the override: the resolved body for `-d`, the file path for `-f`.
- The body passed via CLI is templated with the same variable context as every other field, **including path params** (a request's `type: path` params resolve inside an overridden body), and the manifest body's variables are exempt from the missing-variable preflight once the body is overridden.
- The override flows through the existing curl-argument builder (`--data` for `-d`, `--data @file` for `-f`). When a `-f` file must be templated or is `.jsonc`, its resolved/stripped content is inlined into `--data` (mirroring the REST client's `file_body` mechanism); otherwise curl reads the file via `--data @file`. Dry-run and execution always agree on the exact bytes.
- The HTTP method comes from the manifest and is never changed by the override.

## Testing Decisions

A good test asserts **external behavior only**: the printed `curl` line (dry-run), the stderr message, and the exit code — never internal data structures.

Two seams, both already in use by the existing `oc` tests:

1. **Process boundary (primary, highest seam)** — run `http oc ... -n` as a subprocess with a stub `curl` on `PATH` and a temp `HOME` whose `.httprc` points at a temp collection; assert on stdout, stderr, and exit code. Covers flag emission, the Content-Type precedence, form-urlencoded verbatim, both error cases, `.jsonc` stripping, and templating/preflight.
2. **Module boundary (secondary)** — import the `http` module and unit-test the pure "Comando equivalente" builder for the inclusion of `-d`/`-f`. Prior art: the existing unit tests of that same builder for `-v` and `--dqwnp`.

Prior art for the behaviors mirrored from the REST client (mutual exclusivity, missing-file error, `.jsonc` stripping, empty `-d`) is the existing REST client test suite.

## Out of Scope

- The Go `httpoc` rewrite (paused); this spec targets the Python `http oc` only.
- Adding `-H`/`-q` to the "Comando equivalente" (pre-existing gap, tracked separately).
- Re-encoding form-urlencoded bodies.
- Changes to the REST client (`http post`, etc.) — it already has `-d`/`-f`.
- A `-t`/`--token` flag for `oc`, multipart bodies, and file uploads.
- The curl `--data` gotcha where a leading `@` is interpreted as a file reference — unchanged from today.

## Further Notes

- ADR-0001 records the override semantics and the Content-Type precedence ladder, including the rejected alternatives.
- The Python `oc` subcommand is slated for removal in favor of the Go `httpoc` (on pause). This spec is the authoritative reference for parity if/when the Go rewrite resumes.
- The feature deliberately mirrors the REST client's `-d`/`-f` semantics so muscle memory transfers between the two commands.
