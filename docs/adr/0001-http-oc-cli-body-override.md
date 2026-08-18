# http oc: CLI body override replaces the manifest body

The `http oc` subcommand gains `-d`/`--data` and `-f`/`--file` flags so the request body can be supplied from the command line without editing the collection. When present, the CLI body replaces the manifest's `request.body`, and Content-Type is resolved by precedence: explicit `Content-Type` header (CLI `-H` or manifest-declared), then `-f` file extension, then the manifest `body.type` (for `-d` only), then `application/json` by default.

## Considered Options

- **Full replacement** — the CLI body also discards the manifest `body.type` for Content-Type (defaulting to JSON). Simpler, but it silently changes the Content-Type of a `form-urlencoded` or `text` request to JSON when the user only meant to swap the value. Rejected.
- **Supply only when the manifest has no body** — doesn't solve the actual need (testing a different body without editing the file). Rejected.
