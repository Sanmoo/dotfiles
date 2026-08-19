# 03 — CLI certificate overrides: --cert/--key/--cacert

**What to build:** the `oc` subcommand gains `--cert`, `--key`, and `--cacert` flags. `--cert`/`--key` must be passed together (exit 2 otherwise) and, when present, replace the manifest-matched certificate for the main request of this run. `--cacert` adds server-side trust as a one-off escape hatch and is mutually exclusive with `-k` (exit 2). The Comando equivalente includes the flags when they were used. CLI flags apply to the main request only — token requests keep using the manifest-matched certificates.

**Blocked by:** 01 — Manifest client certificates reach the main request.

**Status:** ready-for-agent

- [ ] `--cert` with `--key` overrides the matched manifest certificate in the executed and dry-run commands
- [ ] `--cert` without `--key` (and vice versa) exits 2 with a clear pairing error
- [ ] `--cacert` adds the CA bundle to the main request's curl command
- [ ] `-k` together with `--cacert` exits 2 with a clear mutually-exclusive error
- [ ] `-k` together with `--cert`/`--key` works (cert+key only, no `--cacert`)
- [ ] CLI certificate flags do not appear on OAuth2 token requests
- [ ] The Comando equivalente printed in interactive mode includes `--cert`/`--key`/`--cacert` when they were passed on the command line
- [ ] Override behaviour is covered at the process boundary (stub curl, dry-run, exit codes)
