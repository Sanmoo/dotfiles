# httpoc Public Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the httpoc repo presentable to a public audience: rewrite the README (self-contained, reproducible), move the petstore fixture to `examples/`, normalize all provenance comments, and surface the CI mirror with a status badge — without changing tool behavior except one approved output rename.

**Architecture:** Docs/content work on a finished Go CLI. Three independent deliverables: (1) fixture move with test-helper updates, (2) comment/output normalization with parity-pin updates, (3) README rewrite + quality-gate doc. Each is independently testable via `make check` and manual command runs.

**Tech Stack:** Go 1.26+, Makefile quality gate, Markdown. No new dependencies. All work in `/home/sanmoo/dev/github.com/Sanmoo/httpoc` (never write to dotfiles or bruno-wrapper).

## Global Constraints

Verbatim from `docs/superpowers/specs/2026-08-03-httpoc-public-readme-design.md` + approved amendments:

- **Copy rule (public-safe):** Replace `http oc` → "the original Python tool" (or drop); `dotfiles/general/bin/http` and any dotfiles path → drop; `bruno-wrapper` → "the deprecated predecessor" (or drop); real collection names (football-data, seguros-unimed, java_learning) in comments → generic ("a real collection"). KEEP: "Python" provenance, module path `github.com/sanmoo/httpoc`, `.httprc`/`.bruwrapper.yaml` feature names, and parity pin string literals — EXCEPT the approved rename below.
- **Output rename (amended):** `buildEquivalentCommand` (internal/app/run.go) must render `httpoc -c <collection> ...` — never `http oc -c ...`. Structure stays identical (parity of shape). All pins updated in lockstep (app_test.go want strings, parity_test.go scenario 24, comments).
- **capture-goldens.sh (amended):** the `DOTFILES=~/dev/github.com/Sanmoo/dotfiles` assignment becomes env-overridable `DOTFILES="${DOTFILES:-$HOME/dev/github.com/Sanmoo/dotfiles}"` with a maintainer-only comment.
- **Single source of truth:** petstore lives at `examples/petstore` (moved, never copied). `testdata/collections/spec/` is deleted (empty after the move).
- **Gate:** `make check` ALL GREEN before every commit (from the httpoc repo root). Coverage stays 100% (1408/1408) — comment-only edits and fixture moves cannot change it; the helper path updates are exercised by existing e2e/catalog tests.
- **Dry-run never fetches tokens (user ruling C, 2026-08-03):** `-n` performs ZERO network I/O — no token-endpoint request, no authorization-code callback. Auth is resolved + validated (unsupported types still exit 2 — parity test 24 preserved) and templated auth fields are still pre-expanded (Task 8 contract). Token in dry-run: bearer → the expanded token field (static, no I/O); oauth2 → cached valid token if present (respecting expiry), else the masked placeholder `***`; `--auth-no-cache` in dry-run → always placeholder. The masked curl line renders `Authorization: Bearer ***` whenever auth is configured (identical after masking, cached or placeholder). Real runs unchanged (fetch as today). This SUPERSEDES parity scenario 25's hitCount pins (and any other dry-run+auth pins) — pins updated, divergence recorded in the ledger.
- **show** does NOT accept `-e` and prints the URL as defined (raw `{{...}}` templates — parity-pinned by TestE2EShow). README quick start uses `httpoc show -c petstore get-pet`; expected output shows the raw template URL.
- **Badge URL** assumes `github.com/sanmoo/httpoc` (matches the module path); the badge renders only once the repo is public — accepted.
- **No other behavior changes.** No new dependencies. No workflow file changes.
- Commit messages: conventional (`refactor(test): …`, `chore: …`, `docs: …`). Commit EARLY and often — wall-clock is the recurring killer.

---

## File Structure

- `examples/petstore/` — the public example collection (moved from testdata): `opencollection.yaml` + `requests/{get,list,create,delete}-pet.yaml`. One clear purpose: a reproducible, spec-1.0.0 collection readers can run against.
- `testdata/collections/spec/` — deleted after the move (petstore was its only content).
- `internal/app/e2e_test.go` — `petstorePath()` helper points at `examples/petstore`.
- `internal/adapters/catalog/catalog_test.go` — `specRoot()` helper points at `examples`.
- ~15 source/test files — doc-comment provenance normalization (mapping in Task 2).
- `README.md` — full public rewrite (12 sections, full draft in Task 3).
- `docs/quality-gate.md` — CI-mirror line update.
- `scripts/capture-goldens.sh` — env-overridable DOTFILES.

---

### Task 1: Move the petstore fixture to examples/ and update test helpers

**Files:**

- Move: `testdata/collections/spec/petstore/` → `examples/petstore/` (directory: `opencollection.yaml`, `requests/get-pet.yaml`, `requests/list-pets.yaml`, `requests/create-pet.yaml`, `requests/delete-pet.yaml`)
- Delete: `testdata/collections/spec/` (now empty)
- Modify: `internal/app/e2e_test.go:150-153` (`petstorePath`)
- Modify: `internal/adapters/catalog/catalog_test.go:19-24` (`specRoot`)

**Interfaces:**

- Consumes: nothing new — `repoRoot(t)` (e2e_test.go:39-43, unchanged) resolves the repo root via `runtime.Caller`.
- Produces: `examples/petstore` as the single public example source; `specRoot(t)` and `petstorePath(t)` keep their exact signatures (later tasks and the README quick start depend on the example living at `examples/petstore`).

- [ ] **Step 1: Move the fixture with git mv**

Run from `/home/sanmoo/dev/github.com/Sanmoo/httpoc`:

```bash
git mv testdata/collections/spec/petstore examples/petstore
rmdir testdata/collections/spec
```

Verify: `ls examples/petstore/requests/` shows the 4 request files; `ls testdata/collections/` shows only `legacy/`.

- [ ] **Step 2: Update `petstorePath`**

In `internal/app/e2e_test.go`, change:

```go
 return filepath.Join(repoRoot(t), "testdata", "collections", "spec", "petstore")
```

to:

```go
 return filepath.Join(repoRoot(t), "examples", "petstore")
```

(keep the function doc comment, but update "the spec fixture collection path" → "the public example collection path").

- [ ] **Step 3: Update `specRoot`**

In `internal/adapters/catalog/catalog_test.go`, change:

```go
 return filepath.Join(filepath.Dir(file), "..", "..", "..", "testdata", "collections", "spec")
```

to:

```go
 return filepath.Join(filepath.Dir(file), "..", "..", "..", "examples")
```

(its 4 call sites — lines 122, 127, 282, 495 — need no changes: `petstore` is still discovered under the root.)

- [ ] **Step 4: Run the gate**

```bash
make check
```

Expected: ALL GREEN (coverage 100%, 1408/1408 — same statements; the e2e petstore dry-run cases now read from `examples/petstore`, proving the move end-to-end).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(test): move spec petstore fixture to examples/ (single public example source)"
```

---

### Task 2: Normalize provenance comments and the equivalent-command output

**Files:**

- Modify: `internal/app/run.go:788-805` (`buildEquivalentCommand`) and `:783-785` (doc comment)
- Modify: `internal/app/app_test.go` — want strings (6 sites, see Step 3)
- Modify: `internal/app/parity_test.go` — scenario 24 pin + comments (scenarios 23/24, header notes at 40-42)
- Modify: doc-comment files listed in the mapping table (Step 1)
- Modify: `scripts/capture-goldens.sh` (Step 2)

**Interfaces:**

- Consumes: the mapping table below (exact strings) — the Task 3 README references "the predecessor tool's config files" generically, so no name survives in user-facing text after this task.
- Produces: zero occurrences of `bruno-wrapper`/`bruno_wrapper`/`http oc`/`http.py` repo-wide; `dotfiles` only inside `scripts/capture-goldens.sh`; the finally-clause output renders `httpoc -c ...`.

- [ ] **Step 1: Apply the comment mapping**

For each row, open the file, locate the line, and apply the exact replacement (substring-level; keep surrounding comment text). After all rows, the doc comments read naturally and never name the private tool/paths:

| File:line | Old text (exact) | New text (exact) |
| --- | --- | --- |
| `cmd/httpoc/main.go:1-2` | `// Command httpoc is the standalone Go rewrite of the Python \`http oc\`\n// tool: run/list/show OpenCollection requests with full parity.` | `// Command httpoc is a standalone HTTP CLI for OpenCollection 1.0.0\n// collections: run/list/show requests with full parity.` |
| `internal/adapters/terminal/formatter.go:3-4` | `// summary, ported from the Python \`http oc\` tool\n// (dotfiles/general/bin/http) and the deprecated bruno-wrapper.` | `// summary, ported from the original Python tool.` |
| `internal/adapters/terminal/formatter.go:28` | `like the bruno-wrapper` | `like the deprecated predecessor` |
| `internal/adapters/terminal/jsonhighlight.go:9` | `in the deprecated bruno-wrapper (Foreground` | `in the deprecated predecessor (Foreground` |
| `internal/adapters/terminal/jsonhighlight.go:37` | `bruno-wrapper's jsonhighlight.go (which used termenv):` | `the deprecated predecessor's jsonhighlight.go (which used termenv):` |
| `internal/adapters/terminal/jsonhighlight.go:76` | `the bruno-wrapper original panicked on it` | `the deprecated predecessor panicked on it` |
| `internal/adapters/terminal/jsonhighlight.go:129` | `as the bruno-wrapper` | `as the deprecated predecessor` |
| `internal/adapters/terminal/jsonhighlight.go:158` | `bruno-wrapper helper; the` | `the predecessor helper; the` |
| `internal/adapters/terminal/jsonhighlight_test.go:124` | `The bruno-wrapper original panicked (slice out of range) on a lone` | `The deprecated predecessor panicked (slice out of range) on a lone` |
| `cmd/httpoc/show.go:12` | `(bruno-wrapper UX)` | `(predecessor UX)` |
| `cmd/httpoc/list.go:12` | `(bruno-wrapper UX)` | `(predecessor UX)` |
| `internal/adapters/auth/cache.go:3` | `the Python reference (dotfiles/general/bin/http: cache_key_for_auth,` | `the Python reference (cache_key_for_auth,` |
| `internal/adapters/auth/cache.go:5` | `resolve_oauth2_token; dotfiles/general/bin/auth-code-token).` | `resolve_oauth2_token).` |
| `internal/adapters/interactive/selector.go:2-3` | `ported from the Python \`http oc\`\n// tool (dotfiles/general/bin/http) choose_with_fzf_or_prompt.` | `ported from the original Python tool's choose_with_fzf_or_prompt.` |
| `internal/adapters/runner/runner.go:2-3` | `and execution, ported from the Python \`http oc\` tool\n// (dotfiles/general/bin/http).` | `and execution, ported from the original Python tool.` |
| `internal/adapters/runner/runner.go:35` | `Python's _PROCESS_ENV_RE in dotfiles/general/bin/http).` | `Python's _PROCESS_ENV_RE in the original tool).` |
| `internal/adapters/runner/curl.go:22` | `of Python build_curl_args for the \`http oc\` path (file=None):` | `of Python build_curl_args (file=None):` |
| `internal/adapters/runner/curl_test.go:164` | `dotfiles/general/bin/http (Task 2); the same resolved inputs the Python` | `the original tool (Task 2); the same resolved inputs the Python` |
| `internal/adapters/catalog/catalog.go:3` | `// \`http oc\` tool (dotfiles/general/bin/http).` | `// the original Python tool.` |
| `internal/adapters/config/config.go:4` | `reference (dotfiles/general/bin/http: load_httprc).` | `reference (load_httprc).` |
| `internal/adapters/config/config_test.go:99` | `// Python parity (dotfiles general/bin/http expand_config_path ->` | `// Python parity (expand_config_path ->` |
| `internal/app/run.go:2-4` | `// use cases, ported from the Python \`http oc\` tool\n// (dotfiles/general/bin/http: main_oc and its helpers) and the deprecated\n// bruno-wrapper UX.` | `// use cases, ported from the original Python tool's main_oc and its\n// helpers, and from its successor.` |
| `internal/app/show.go:11` | `it (bruno-wrapper ShowRequestDetails shape)` | `it (predecessor ShowRequestDetails shape)` |
| `internal/app/show.go:56` | `(bruno-wrapper maskSensitive parity:` | `(predecessor maskSensitive parity:` |
| `internal/app/resolve.go:3` | `Python \`http oc\` tool (dotfiles/general/bin/http).` | `the original Python tool.` |
| `internal/app/list.go:10` | `collection (bruno-wrapper output shape:` | `collection (predecessor output shape:` |
| `internal/app/e2e_test.go:272` | `TestE2EList pins the bruno-wrapper-shaped list output.` | `TestE2EList pins the predecessor-shaped list output.` |
| `internal/app/e2e_test.go:311` | `TestE2EShow pins the bruno-wrapper-shaped show output.` | `TestE2EShow pins the predecessor-shaped show output.` |
| `internal/app/run.go:783` | `// (build_equivalent_command parity): http oc -c <collection> [-e <env>]` | `// (build_equivalent_command parity): httpoc -c <collection> [-e <env>]` |
| `scripts/capture-goldens.sh:2` | `# Captures dry-run stdout baselines from the Python \`http oc\` (parity axis A).` | `# Maintainer-only: regenerates dry-run stdout baselines from the original\n# (private) Python tool, parity axis A.` |
| `scripts/capture-goldens.sh:4` | `# One golden per scenario in dotfiles/tests/http-oc-test.sh that (a) runs with` | `# One golden per scenario in the original tool's test suite that (a) runs with` |
| `scripts/capture-goldens.sh:19` | `DOTFILES=~/dev/github.com/Sanmoo/dotfiles` | `DOTFILES="${DOTFILES:-$HOME/dev/github.com/Sanmoo/dotfiles}"` |

Skip (KEEP as-is): `internal/app/parity_test.go` hits of `.httprc`/`.bruwrapper.yaml` (feature behavior) and any "Python"–only mentions. If `rg` finds a hit NOT in this table, do not invent a replacement — record it and stop (report back instead).

- [ ] **Step 2: Rename the equivalent-command output**

In `internal/app/run.go:788-805` (`buildEquivalentCommand`), change the command prefix:

```go
 cmd := []string{"http", "oc", "-c", collectionName}
```

to:

```go
 cmd := []string{"httpoc", "-c", collectionName}
```

Nothing else in the function changes (env/vars/dqwnp/request assembly stays identical).

- [ ] **Step 3: Update the pinned expectations in lockstep**

In `internal/app/app_test.go`:

- Line 1091: `want := "Comando equivalente: http oc -c collectionA -e development get-smart-conditions\n"` → replace `http oc` with `httpoc`.
- Line 1114: `want := "Comando equivalente: http oc -c collectionDqwnp -v limit=20 --dqwnp search\n"` → same replacement.
- Table rows at 1504, 1508, 1513, 1517, 1522, 1527: every `want: "http oc -c ..."` value → `"httpoc -c ..."` (same replacement, nothing else).

In `internal/app/parity_test.go`:

- Scenario 24 (line ~760): the contains-pin `[]string{"Comando equivalente: http oc -c collectionA -e development ping"}` → `[]string{"Comando equivalente: httpoc -c collectionA -e development ping"}`.
- Scenario 24 comment (line ~757): "the Python-shaped `http oc -c ...` equivalent command verbatim" → "the equivalent command in the Python shape, tool renamed to httpoc (public-name amendment)".
- Scenario 23 comment (line ~749): `// Python "Comando equivalente: http oc -c ..." line (pinned below).` → `// Python "Comando equivalente: http oc -c ..." line (the Go shape pins its absence below).`
- The `[]string{"http oc -c"}` notOut pin in scenario 23 STAYS (it pins the divergence — the summary never prints it; still true after the rename).
- Header comment at lines 40-42: replace `http oc -c` with `httpoc -c` where it describes the Go shape; leave the Python-describing clause as-is.

- [ ] **Step 4: Verify zero residual references**

Run:

```bash
rg -n "bruno-wrapper|bruno_wrapper|http oc|http\.py|general/bin/http" --hidden -g '!.git' -g '!cover.out' .
rg -n "dotfiles" --hidden -g '!.git' -g '!cover.out' .
rg -n "\.httprc|\.bruwrapper" --hidden -g '!.git' -g '!cover.out' . | head -20
```

Expected: first command → no output. Second → hits ONLY in `scripts/capture-goldens.sh` (the env default + comments). Third → hits only in feature tests/comments (config, parity) — KEEP.

- [ ] **Step 5: Run the gate**

```bash
make check
```

Expected: ALL GREEN — the updated pins compile and pass with the renamed output; parity suite still 33/33 (scenario 24 asserts the renamed line).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: normalize provenance comments and equivalent-command output for public repo"
```

---

### Task 3: Dry-run never fetches tokens (cache-or-mask)

**Files:**

- Modify: `internal/core/ports.go` — add `TokenFromCache(ctx context.Context, spec AuthSpec) (string, bool)` to the `AuthProvider` port
- Modify: `internal/adapters/auth/oauth.go` — implement `TokenFromCache` (cache lookup only, no network, bearer → ok=false)
- Modify: `internal/app/run.go` — split `doAuth` (lines ~627-645) into resolve+validate+expand (no I/O) and acquisition; `complete()` (line ~150) uses the dry-run token path when `args.DryRun`
- Modify: `internal/app/app_test.go` — fakeAuth gains `TokenFromCache`; dry-run+auth unit tests updated per the new contract
- Modify: `internal/app/parity_test.go` — scenarios 21/22/25 pins superseded (see contract)
- Modify: `internal/adapters/auth/auth_test.go` — new `TokenFromCache` tests
- Modify: `cmd/httpoc/root.go` — `--auth-no-cache` help text gains "(no effect with -n)"
- Verify: `internal/app/e2e_test.go` — must stay GREEN UNCHANGED (seeded cache → TokenFromCache reads it → identical masked lines)

**Interfaces:**

- Consumes: existing `CacheKey(collectionPath, envName, a)` (internal/adapters/auth/cache.go:60), `p.cached(key, forceRefresh)` (cache lookup with expiry), `core.Auth.Type`/`Flow`.
- Produces: `AuthProvider.TokenFromCache(ctx, spec) (string, bool)` — ok=true only for a valid, non-expired cached oauth2 token; ok=false for bearer, no cache, or expired. `f.resolveAuth(...)` and `f.acquireToken(...)` replace `doAuth`.

- [ ] **Step 1: Write the failing tests (contract first)**

In `internal/adapters/auth/auth_test.go`, add `TestTokenFromCache` (table): (a) client_credentials with a saved token → (token, true); (b) no cache → ("", false); (c) expired cache → ("", false); (d) bearer spec → ("", false).

In `internal/app/app_test.go`, update/add: (e) dry-run + oauth2 + NO cache → exit 0, output contains `Authorization: Bearer ***`, and the fake auth's Token was NOT called (fake records calls); (f) dry-run + oauth2 + `--auth-no-cache` → same, TokenFromCache not called; (g) dry-run + bearer → masked line with the expanded token value masked; (h) dry-run + unsupported auth type → still exit 2 (parity 24 preserved).

- [ ] **Step 2: Run them — verify they fail**

`go test ./internal/app ./internal/adapters/auth -run 'TestRun|TestTokenFromCache'` — expect compile errors (missing port method) then failures.

- [ ] **Step 3: Implement the port + adapter**

In `internal/core/ports.go`, add to the `AuthProvider` interface:

```go
 // TokenFromCache returns the cached access token for an oauth2 spec
 // without any network I/O (dry-run path, user ruling 2026-08-03):
 // ok=false for bearer auth, a missing cache entry, or an expired
 // token.
 TokenFromCache(ctx context.Context, spec AuthSpec) (string, bool)
```

In `internal/adapters/auth/oauth.go`, implement:

```go
func (p *Provider) TokenFromCache(ctx context.Context, spec core.AuthSpec) (string, bool) {
 a := spec.Auth
 if a == nil || a.Type != "oauth2" {
  return "", false
 }
 cached, err := p.cached(CacheKey(spec.CollectionPath, spec.EnvironmentName, a), false)
 if err != nil || cached == nil {
  return "", false
 }
 return cached.AccessToken, true
}
```

- [ ] **Step 4: Split doAuth in the app layer**

In `internal/app/run.go`, replace `doAuth` (currently resolves + validates + expands + calls Token) with two functions:

```go
// resolveAuth resolves the request auth (three-level inheritance),
// validates it, and pre-expands every templated field (no I/O; nil auth
// yields nil — Python get_oc_auth + validate_supported_oc_auth parity).
func (f *flow) resolveAuth(request core.Request, collection core.Collection, envName string, variables map[string]string) (*core.Auth, error) {
 auth := core.ResolveAuth(&request, collection.Manifest)
 if auth == nil {
  return nil, nil
 }
 if err := core.ValidateAuth(auth); err != nil {
  return nil, err
 }
 return expandAuth(auth, variables, f.deps.Stderr), nil
}

// acquireToken obtains the token (Python resolve_oauth2_token parity —
// network + cache). Only called for real runs; dry-run uses dryRunToken.
func (f *flow) acquireToken(ctx context.Context, collection core.Collection, envName string, auth *core.Auth) (string, error) {
 return f.deps.Auth.Token(ctx, core.AuthSpec{
  CollectionPath:  collection.Path,
  EnvironmentName: envName,
  Auth:            auth,
 }, f.args.AuthNoCache)
}

// dryRunToken returns the token for a dry-run: bearer auth yields its
// static expanded token; oauth2 yields the cached token when present and
// not expired, otherwise the masked placeholder (user ruling C: dry-run
// never fetches).
func (f *flow) dryRunToken(ctx context.Context, collection core.Collection, envName string, auth *core.Auth) string {
 if auth.Type != "oauth2" {
  return auth.Token
 }
 if f.args.AuthNoCache {
  return "***"
 }
 tok, ok := f.deps.Auth.TokenFromCache(ctx, core.AuthSpec{
  CollectionPath:  collection.Path,
  EnvironmentName: envName,
  Auth:            auth,
 })
 if !ok {
  return "***"
 }
 return tok
}
```

In `complete()` (line ~150), replace the `doAuth` call with:

```go
 auth, err := f.resolveAuth(request, sel.collection, sel.envName, variables)
 if err != nil {
  return f.fail(ctx, err)
 }
 token := ""
 if auth != nil {
  if f.args.DryRun {
   token = f.dryRunToken(ctx, sel.collection, sel.envName, auth)
  } else {
   token, err = f.acquireToken(ctx, sel.collection, sel.envName, auth)
   if err != nil {
    return f.fail(ctx, err)
   }
  }
 }
```

- [ ] **Step 5: Update the superseded parity pins**

Read scenarios 21, 22, 25 in `internal/app/parity_test.go` in full. Under ruling C: dry-run performs zero network I/O. Update every pin that asserts a token-endpoint hit, callback-server activity, or a dry-run failure caused by an unreachable token endpoint — hitCount assertions become 0 (with a comment `// user ruling 2026-08-03: dry-run never fetches tokens`), masked-line assertions stay, and any callback-server assertions become "server not started/not hit" assertions. Also update any app unit test that expected dry-run to fail on token-fetch errors (now exit 0 with the masked line). Run `go test ./... -count=1` and let the failures enumerate any pin you missed; fix them all.

- [ ] **Step 6: e2e must stay unchanged and green**

`go test -count=1 -run 'TestE2E' ./internal/app` — expect ALL GREEN with NO changes to `internal/app/e2e_test.go` (seeded cache → TokenFromCache reads it → identical masked want lines). If any e2e test fails, stop and report — that signals the cache key mismatch (FIX-1 class bug), not a pin to update.

- [ ] **Step 7: Run the full gate**

```bash
make check
```

Expected: ALL GREEN — coverage 100% incl. the new branches (TokenFromCache hit/miss/expired/bearer; dryRunToken oauth2 cached/miss/noCache; bearer dry-run), parity 33/33 with superseded pins, lint numeric gates. Paste coverage + gate lines as evidence.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(run): dry-run never fetches tokens (cache-or-mask, user ruling C)"
```

---

### Task 4: Rewrite the README and update the quality-gate doc

**Files:**

- Modify: `README.md` — full rewrite to the draft below (12 sections)
- Modify: `docs/quality-gate.md:1` — first line

**Interfaces:**

- Consumes: `examples/petstore` (Task 1) and the renamed output (Task 2) — the quick start must work exactly as written against the moved example.
- Produces: the public-facing entry point; readers can reproduce every command with only the repo cloned.

- [ ] **Step 1: Replace README.md with the full draft**

Write the following to `README.md` (complete file — no sections omitted):

````markdown
# httpoc

A standalone HTTP CLI for [OpenCollection](https://opencollection.dev) 1.0.0
collections: one-shot requests, request discovery, variable resolution, OAuth2
flows, and a curl-equivalent dry-run — all from the terminal, with no server.

`httpoc` reads collection directories that follow the OpenCollection 1.0.0
spec (`opencollection.yaml` manifest + HTTP request documents) and runs them
from a single static Go binary: no Python, no PyYAML, no curl, no fzf
required.

## Features

- **Spec-shaped discovery** — walks your collection roots and finds
  OpenCollection 1.0.0 manifests (`opencollection.yaml` …) plus HTTP request
  documents (`info.type: http` or an `http:` block), without a server.
- **Run / list / show** — execute a request, list collections or requests, or
  print a request's method and URL without executing.
- **Variables & environments** — collection variables, `config.environments`,
  CLI `-v KEY=VALUE`, path-param binding, and optional-query disabling
  (`--dqwnp`), with a single precedence order and interactive prompts.
- **Auth** — bearer tokens and OAuth2 (client credentials and authorization
  code with PKCE), with a token cache under `~/.cache/httpoc`.
- **Dry-run** — print the equivalent `curl` command without touching the
  network; token values are masked.
- **Interactive selection** — a fuzzy picker when `fzf` is installed,
  otherwise a numbered menu; both work on plain stdin.
- **Portable** — one static binary for linux/darwin × amd64/arm64. With an
  empty `PATH` the binary still runs: it never execs `curl` or `fzf`.

## Install

### From source

```sh
go install github.com/sanmoo/httpoc@latest
```

This requires Go ≥ 1.26 and puts `httpoc` in `$(go env GOPATH)/bin`.

### Release binaries

Each release publishes prebuilt binaries for linux and darwin, amd64 and
arm64, attached to the GitHub release:

- `httpoc-linux-amd64`
- `httpoc-linux-arm64`
- `httpoc-darwin-amd64`
- `httpoc-darwin-arm64`

Download the one for your platform, make it executable, and move it onto your
`PATH`:

```sh
chmod +x httpoc-linux-amd64
sudo mv httpoc-linux-amd64 /usr/local/bin/httpoc
```

## Quick start

### 1. Get the example collection

Clone the repository (or copy `examples/petstore/` anywhere):

```sh
git clone https://github.com/sanmoo/httpoc
cd httpoc
```

### 2. Configure collection roots

`httpoc` reads `~/.config/httpoc/config.yaml`:

```yaml
collections:
  - ./examples   # relative to the current directory; run from the repo root
```

Roots may point at a collection directory directly or at a parent directory
containing several; discovery walks recursively and stops at the first
manifest. A leading `~/` expands against `$HOME`.

### 3. Try it

```sh
httpoc list                          # all discovered collections
httpoc list -c petstore              # all requests in one collection
httpoc show -c petstore get-pet      # method and URL as defined
httpoc -c petstore -e development get-pet -n   # dry-run (no network)
httpoc -c petstore -e development create-pet -v petName=rex -n
```

The `-n` dry-run prints the equivalent `curl` command without touching the
network — OAuth2 collections show a masked `Authorization: Bearer ***`
header and never request a token — so it works with no API at all. To
execute for real, point the `baseUrl` variable in
`examples/petstore/opencollection.yaml` at your own API.

With no `-c` or request name, `httpoc` prompts interactively: a fuzzy picker
when `fzf` is on `PATH`, a numbered menu otherwise.

## Collection format

A collection is a directory with an `opencollection.yaml` manifest and HTTP
request documents. `examples/petstore/opencollection.yaml`:

```yaml
opencollection: 1.0.0
info:
  name: petstore
variables:
  - name: defaultHeader
    value: from-collection
config:
  environments:
    - name: development
      variables:
        - name: baseUrl
          value: https://dev.example.com
        - name: petId
          value: env-pet
```

…and one request, `examples/petstore/requests/get-pet.yaml`:

```yaml
info:
  name: get-pet
  type: http
  seq: 1
http:
  method: GET
  url: "{{baseUrl}}/pets/{{petId}}"
  headers:
    - name: Accept
      value: application/json
    - name: X-Default
      value: "{{defaultHeader}}"
  params:
    - name: verbose
      value: "true"
      type: query
settings:
  encodeUrl: true
```

`{{...}}` placeholders resolve against environment variables, collection
variables, and CLI `-v` overrides, in that precedence order.

## Command reference

`httpoc [run] <request> [flags]` — the root command doubles as `run`.

| Command | Description |
| --- | --- |
| `httpoc [run] <request>` | Resolve and execute one request (any HTTP status is a completed run) |
| `httpoc list` | List discovered collections |
| `httpoc list -c <collection>` | List the requests of one collection |
| `httpoc show -c <collection> <request>` | Print method and URL without executing |
| `httpoc version` | Print the build version |

### Flags (root and `run`)

| Flag | Description |
| --- | --- |
| `-c, --collection <name>` | Collection name (or directory name) |
| `-e, --environment <name>` | Environment name |
| `-v, --var KEY=VALUE` | Variable (repeatable; comma-separated values) |
| `-n, --dry-run` | Print the equivalent curl command without executing |
| `-i, --include` | Include the response status line and headers |
| `-k, --insecure` | Skip TLS certificate verification |
| `-L, --follow` | Follow redirects |
| `-H, --header 'Name: value'` | Extra header (repeatable) |
| `-q, --query key=value` | Extra query pair (repeatable) |
| `--dqwnp[=a,b]` | Omit selected query parameters when their variables are not explicitly provided; omit the value to apply to all queries |
| `--no-interactive` | Never prompt; fail when input is missing |
| `--auth-no-cache` | Force OAuth token regeneration, ignoring the cache |

## Configuration

`httpoc` reads `~/.config/httpoc/config.yaml`:

```yaml
collections:
  - ~/collections
  - ~/collections/my-api   # or point directly at one collection
cache_dir: ~/.cache/httpoc   # optional; this is the default
```

(Config key is `cache_dir`, matching the design §9 example.)

Environments are defined per collection, in its `opencollection.yaml`
manifest (`config.environments`, see [Collection format](#collection-format));
the `-e` flag selects one at run time.

On first run, when `~/.config/httpoc/config.yaml` does not exist yet, `httpoc`
imports collection roots from the predecessor tool's config files
(`~/.config/.httprc` and `~/.bruwrapper.yaml`, in that order, deduplicated)
and creates the config for you. Legacy files are read, never modified.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Completed (any HTTP status, including 4xx/5xx) |
| `2` | Any error: bad flags, missing config, unknown collection/request, missing variables, transport failure, unsupported auth |
| `130` | Interrupted (SIGINT) or aborted interactive selection |

## Quality gate

[![ci](https://github.com/sanmoo/httpoc/actions/workflows/ci.yml/badge.svg)](https://github.com/sanmoo/httpoc/actions/workflows/ci.yml)

The official quality protocol runs locally: **`make check`** must be green
before any commit or completion claim.

```sh
make check
```

See [docs/quality-gate.md](docs/quality-gate.md) for the full protocol. The
GitHub Actions pipeline
([.github/workflows/ci.yml](.github/workflows/ci.yml)) mirrors the same gate
on every push.

## Development

```sh
make check        # the full quality gate: lint, test, coverage, mutation, parity, vuln
make lint         # golangci-lint run ./...
make test         # go test -race -count=1 ./...
make coverage     # coverage profile + go-test-coverage thresholds (100% per file/package/total)
make mutate       # gremlins mutation gate (core+app packages, ≥85% efficacy)
make parity       # parity + e2e tests only (TestParity|TestE2E)
make vuln         # govulncheck ./...
make build        # build ./cmd/httpoc into dist/httpoc
make release      # build the 4 release binaries into dist/
```

The repo layout mirrors the design: `cmd/httpoc` (CLI composition),
`internal/core` (domain model and ports), `internal/app` (orchestration),
`internal/adapters` (catalog, config, runner, auth, interactive, terminal).

## Roadmap

Shipped in v1: run/list/show, spec-shaped discovery, variables and
environments, bearer + OAuth2 (client credentials, authorization code with
PKCE), token cache, dry-run with curl-equivalent output, legacy migration,
interactive selection, standalone operation.

Deferred to later phases:

- **Assertions** — response validation (status, JSON path, headers) as first-class request checks
- **Scripts** — reusable pre/post-request scripts in the collection
- **Request chaining** — passing response values (e.g. tokens, ids) into subsequent requests
- gRPC, GraphQL and WebSocket transports; embedded fuzzy picker (PTY)

## License

MIT — see [LICENSE](LICENSE).
````

Notes on the draft (do not deviate): the `show` line takes no `-e` and prints the URL as defined (raw `{{...}}` templates — parity-pinned); the Configuration snippet shows the REAL config schema (`collections` + optional `cache_dir`, per `internal/adapters/config/config.go`); environments live in the collection manifest, never in config.yaml; the migration clause is the approved generic wording; the badge URL is the approved one.

- [ ] **Step 2: Update the quality-gate doc**

In `docs/quality-gate.md`, change the first line:

```markdown
Local protocol enforced by AI agents (no CI server).
```

to:

```markdown
Local protocol enforced by AI agents; the GitHub Actions pipeline mirrors the same gate on push.
```

- [ ] **Step 3: Verify the quick start works exactly as written**

Build and run against the example (from the repo root; config is not needed —
the commands use `-c petstore` with discovery from `./examples` via a temp
config):

```bash
go build -o /tmp/httpoc ./cmd/httpoc
mkdir -p /tmp/httpoc-home/.config/httpoc
printf 'collections:\n  - %s\n' "$(pwd)/examples" > /tmp/httpoc-home/.config/httpoc/config.yaml
HOME=/tmp/httpoc-home /tmp/httpoc list
HOME=/tmp/httpoc-home /tmp/httpoc list -c petstore
HOME=/tmp/httpoc-home /tmp/httpoc show -c petstore get-pet
HOME=/tmp/httpoc-home /tmp/httpoc -c petstore -e development get-pet -n
HOME=/tmp/httpoc-home /tmp/httpoc -c petstore -e development create-pet -v petName=rex -n
```

Expected: `list` shows the petstore collection; `list -c petstore` shows
get-pet/list-pets/create-pet/delete-pet; `show` prints the method and the
URL as defined — raw `{{baseUrl}}/pets/{{petId}}` templates, parity-pinned
(Task 3's ruling does not change show); BOTH dry-runs print a masked
`Authorization: Bearer ***` curl line and exit 0 — offline, no token
endpoint reachable (Task 3's ruling makes this true). Use an absolute root
here (`~` expansion is HOME-based); the README's `./examples` relative form
works for readers at the repo root. Clean up `/tmp/httpoc` and
`/tmp/httpoc-home` afterwards.

- [ ] **Step 4: Run the gate**

```bash
make check
```

Expected: ALL GREEN (README/docs edits cannot affect it — gate is evidence).

- [ ] **Step 5: Commit**

```bash
git add README.md docs/quality-gate.md
git commit -m "docs: rewrite README for public audience with reproducible quick start"
```

---

## Self-Review (controller runs after writing this plan)

1. **Spec coverage:** 12-section README (Task 3 draft) ✓; examples move + single source (Task 1) ✓; comment rule + KEEP list (Task 2 Step 1 table) ✓; migration clause generic (Task 3 draft §Configuration) ✓; output rename + pins (Task 2 Steps 2-3) ✓; capture-goldens env var (Task 2 Step 1 row) ✓; CI badge + mirror wording (Task 3 draft §Quality gate + Step 2) ✓; badge dead-until-public accepted (Global Constraints) ✓; out-of-scope items untouched ✓.
2. **Placeholder scan:** every step has exact content; the README draft is complete; the mapping table lists every known hit with exact strings; the unknown-hit escape hatch is explicit (record and stop — not invent).
3. **Consistency:** `examples/petstore` path consistent across Task 1 helpers and Task 3 commands; `httpoc -c ...` output consistent across Task 2 pins; specRoot/petstorePath signatures unchanged; commit message conventions consistent.
