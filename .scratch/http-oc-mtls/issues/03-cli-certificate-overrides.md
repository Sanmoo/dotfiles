# 03 — CLI certificate overrides: --cert/--key/--cacert

**What to build:** the `oc` subcommand gains `--cert`, `--key`, and `--cacert` flags. `--cert`/`--key` must be passed together (exit 2 otherwise) and, when present, replace the manifest-matched certificate for the main request of this run. `--cacert` adds server-side trust as a one-off escape hatch and is mutually exclusive with `-k` (exit 2). The Comando equivalente includes the flags when they were used. CLI flags apply to the main request only — token requests keep using the manifest-matched certificates.

**Blocked by:** 01 — Manifest client certificates reach the main request.

**Status:** resolved

- [x] `--cert` with `--key` overrides the matched manifest certificate in the executed and dry-run commands
- [x] `--cert` without `--key` (and vice versa) exits 2 with a clear pairing error
- [x] `--cacert` adds the CA bundle to the main request's curl command
- [x] `-k` together with `--cacert` exits 2 with a clear mutually-exclusive error
- [x] `-k` together with `--cert`/`--key` works (cert+key only, no `--cacert`)
- [x] CLI certificate flags do not appear on OAuth2 token requests
- [x] The Comando equivalente printed in interactive mode includes `--cert`/`--key`/`--cacert` when they were passed on the command line
- [x] Override behaviour is covered at the process boundary (stub curl, dry-run, exit codes)

## Comments

- Implemented in `general/bin/http`; asserted in `tests/http-oc-test.sh` (tests 73–79).
- The `oc` parser gains `--cert`, `--key`, `--cacert`. `build_curl_args` turns an `args.cacert` into `--cacert` (like `cert`/`key`/`passphrase`), and `make_direct_args_from_oc` carries `cacert` onto the direct args, so the main request and its dry-run always agree.
- `main_oc` validates up front, before anything is sent: `--cert`/`--key` must be provided together (exit 2 otherwise), and `--cacert` is mutually exclusive with `-k`/`--insecure` (exit 2). Both are covered for the `-k`/`--insecure` spellings.
- Override: manifest selection and its global structural validation still run (malformed entries fail as before); when CLI `--cert`/`--key` are present they replace the matched certificate on the direct args and clear `passphrase` (there is no `--pass` CLI flag). `-k` + `cert`/`key` passes cert+key only, with no `--cacert`. Note: because selection (including the matched entry's `file not found` check) runs before the override branch, a CLI override cannot bypass a matching manifest entry whose files are missing — the same behavior issue 01 codified for matched entries.
- CLI flags reach only the main request: the OAuth2 token calls (`run_client_credentials`/`run_authorization_code`) build their own curl commands and never see the CLI cert flags. Test 78 captures the token invocation at the process boundary and asserts no `--cert`/`--key`/`--cacert` in it, while the main-request dry-run still shows them.
- `build_equivalent_command` and `print_oc_summary` gain `cert`/`key`/`cacert` params and append `--cert`/`--key`/`--cacert` to the equivalent command when passed; `main_oc` and the interactive summary thread `args.cert`/`args.key`/`args.cacert` through. Unit test 79 asserts the builder includes the flags when used and omits them when absent (manifest-matched certs reproduce for free via collection/environment selection, unchanged).
- Tests: process-boundary seams 73–78 (override in executed + dry-run, pairing errors, `--cacert` add + co-existence with a manifest cert, `-k`×`--cacert` across both spellings, `-k`+cert/key, token-request hygiene); module-boundary unit test 79 for the equivalent-command builder.
