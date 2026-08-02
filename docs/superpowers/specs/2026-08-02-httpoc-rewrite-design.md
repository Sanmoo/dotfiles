# `httpoc` — Go rewrite design (successor of `http oc`)

## 1. Problem Statement

The `oc` subcommand of `general/bin/http` (a 1126-line single-file Python script in
this dotfiles repo) is heavily used for ad-hoc API consumption against
OpenCollection collections. It has grown to ~760 lines of oc-specific logic and
faces three structural problems:

1. **Coupling**: the oc logic is embedded in the REST-client script; importing
   anything from oc pulls in the whole file. The file is approaching the limit of
   what can be maintained safely in one unit.
2. **Format drift**: the Python parser reads the *legacy* request shape (a
   `request:` block). The official OpenCollection 1.0.0 spec (published at
   github.com/opencollection-dev/opencollection, maintained by Bruno) defines the
   `info.type: http` + `http:` block shape. The user's converted collections
   (`*-opencollection` dirs) are spec-compliant and are not fully readable by the
   current parser.
3. **Runtime coupling**: execution depends on `curl` and interactive selection
   depends on `fzf` being pre-installed — a barrier for sharing with a work team
   and with the open-source community.

There is also a parallel tool, `bruno-wrapper` (Go, hexagonal), with good UX
(`list`/`show`/`run`, pretty JSON) but it is not standalone either — it wraps the
`bru` CLI. The user has already been deprecating it.

## 2. Goals and Non-Goals

### Goals

- A standalone Go CLI, single binary, with **zero external runtime dependencies**
  (no `curl`, no `fzf`, no `bru`, no Python).
- Parse the **official OpenCollection 1.0.0 spec** (only; no legacy shapes).
- **Behavioral parity** with `http oc` for everything it does today (flags,
  OAuth2 flows, token cache, templating, optional queries, dry-run, equivalent
  curl command).
- Absorb the `bruno-wrapper` UX: `list`, `show`, pretty-printed JSON.
- Designed for the growth path: assertions, scripts, request chaining,
  GraphQL/gRPC/WebSocket (later phases, per demand).
- A **quality gateway** enforced locally (solo dev, no CI server): 100% coverage
  with explicit exclusion list, mutation testing, static analysis with numeric
  code-quality gates.
- Distribute via `go install` and compiled release binaries (Linux/macOS ×
  amd64/arm64).

### Non-Goals (v1)

- Reading legacy formats (`.bru` classic, `request:`-block YAML) — conversion is
  the migration path (`bruno-oc-converter` / `@opencollection/converters`).
- Assertions, scripts, chaining, GraphQL, gRPC, WebSocket execution.
- PTY-based interaction tests.
- Remote CI (GitHub Actions file ships dormant; free tier works if the repo goes
  public, but nothing depends on it).
- `--fail` / status-based exit codes (arrives with assertions in a later phase).

## 3. Recorded Decisions

| # | Decision |
|---|---|
| 1 | Language: **Go**, single static binary |
| 2 | Format: **OpenCollection 1.0.0 only**, official spec keys |
| 3 | Name: **`httpoc`** (`oc` collides with OpenShift CLI; `http` collides with httpie) |
| 4 | Architecture: **hexagonal** (core / app / adapters), mirroring `bruno-wrapper` |
| 5 | `bruno-wrapper` → **deprecated**; `httpoc` is the successor of `http oc` |
| 6 | Distribution: `go install github.com/sanmoo/httpoc@latest` + gh release binaries |
| 7 | Module: `github.com/sanmoo/httpoc` |
| 8 | Quality gateway runs **locally via Makefile, executed by AI agents** (no CI server) |

## 4. Repository Layout

```
httpoc/
├── cmd/httpoc/main.go          # composition root (wiring only)
├── internal/
│   ├── core/                   # pure domain, zero external deps
│   │   ├── model.go            # Collection, Request, Environment, Auth, Settings...
│   │   └── ports.go            # Catalog, Runner, AuthProvider, TokenCache, Selector, Formatter
│   ├── app/                    # use cases
│   │   ├── run.go              # the `run` use case (mirrors Python main_oc)
│   │   ├── list.go             # list collections/requests
│   │   ├── show.go             # show request details
│   │   └── resolve.go          # variable resolution, optional queries, templating
│   └── adapters/
│       ├── catalog/            # OC YAML parser + discovery (manifest + request docs)
│       ├── runner/             # net/http execution + equivalent-curl builder
│       ├── auth/               # oauth2 (client credentials + authorization code) + token cache w/ lock
│       ├── terminal/           # output: pretty JSON, headers, interactive summary
│       ├── interactive/        # embedded selector (io.Reader seam) + fzf adapter
│       └── config/             # ~/.config/httpoc/config.yaml + legacy migration
├── testdata/
│   ├── collections/            # spec-compliant fixture collections
│   └── golden/                 # dry-run parity baselines
├── coverage.yaml               # exclusion list (see §11)
├── .golangci.yml               # numeric gates (see §11)
├── Makefile                    # the quality gateway entry point
├── .github/workflows/ci.yml    # dormant
├── LICENSE / README.md
└── docs/quality-gate.md        # agent protocol
```

Migrated from `bruno-wrapper` (already tested): `terminal/jsonhighlight.go`,
`terminal/formatter.go`, `interactive/selector.go` (fzf adapter), `cmd/` cobra
pattern. The `.bru` parser stays behind.

## 5. Domain Model (`internal/core/model.go`)

Aligned to the published OpenCollection 1.0.0 JSON Schema.

```go
type Collection struct {
    Name     string    // info.name (fallback: dir name)
    Path     string
    Manifest *Manifest
}

type Manifest struct {
    Version         string            // opencollection: "1.0.0"
    Info            Info              // name, version, author
    Variables       []Variable        // collection-level defaults
    RequestDefaults *Auth             // request.auth inheritance
    Config          CollectionConfig  // proxy, environments (only what v1 uses)
}

type Request struct {
    Name     string         // info.name (fallback: file stem)
    Seq      int            // info.seq
    Path     string
    HTTP     HTTPDetails    // info.type == "http" + http: block
    Settings RequestSettings
}

type HTTPDetails struct {
    Method  string
    URL     string
    Headers []Param         // {name, value, disabled}
    Params  []Param         // type: query | path  (spec has NO type: header)
    Body    *Body           // v1: raw + form-urlencoded; multipart/file later
    Auth    *Auth
}

type Param struct {
    Name     string
    Value    string
    Type     string          // "query" | "path"
    Disabled bool
}

type Auth struct {
    Type   string           // v1: oauth2 | basic | bearer | none
    OAuth2 *OAuth2Config    // grantType, tokenUrl, authUrl, clientId, scope, pkce
}

type Environment struct {
    Name      string
    Variables []Variable
}
```

**Inheritance rules (ported from Python, spec-aligned):**

- `auth`: request `http.auth` → request top-level `auth` → collection `request.auth` → none
- `variables` precedence: CLI `-v` > environment > request > collection
- `path` params become template variables before URL resolution (`{{id}}` in URL)
- only oauth2 grant types `client_credentials` and `authorization_code` in v1
  (matches Python's `validate_supported_oc_auth`); unsupported auth types → clear error

## 6. Ports (`internal/core/ports.go`)

```go
type Catalog interface {
    DiscoverCollections(ctx context.Context, roots []string) ([]Collection, error)
    Requests(ctx context.Context, c Collection) ([]Request, error)
    Environments(ctx context.Context, c Collection) ([]Environment, error)
}

type Runner interface {
    Run(ctx context.Context, req *BuiltRequest, opts RunOptions) (int, error) // streams body to stdout
}

type AuthProvider interface {
    Token(ctx context.Context, spec *AuthSpec, forceRefresh bool) (string, error)
}

type TokenCache interface {
    Get(key string) (*CachedToken, error)   // nil if absent/expired
    Set(key string, tok *CachedToken) error // 0600, atomic write
}

type Selector interface {
    Choose(items []string, label string) (int, error)  // embedded picker or fzf
}

type Formatter interface {
    Summary(...)   // interactive summary + "Comando equivalente"
    Response(...)  // pretty JSON on TTY, raw otherwise
}
```

Design for testability: `Selector` reads from an injected `io.Reader` (scripted
keypresses in tests); the fzf adapter is tested with a fake `fzf` binary on PATH
that echoes the chosen line.

## 7. Data Flow (`httpoc run`)

```
cmd/httpoc (cobra)
  → app.Run (use case)
      1. config.Load()                  → roots, cache_dir (adapters/config)
      2. catalog.DiscoverCollections    → collection (arg -c or selector)
      3. catalog.Requests               → request (positional arg or selector)
      4. catalog.Environments           → env (arg -e or selector)
      5. resolve.Resolve()              → CLI vars + env + collection/request vars
                                          + {{process.env.X}} + path params
                                          + optional-query selection (--dqwnp)
                                          + prompt for missing variables (interactive)
      6. auth.Token()                   → oauth2 (CC or auth code) with cache
      7. build request                  → net/http with headers/query/body/content-type
      8. runner.Run()                   → stream response to stdout
                                          or dry-run: print equivalent curl
      9. exit code                      → 0 | 1 | 2 | 130
```

## 8. CLI Surface

Flags identical to the Python tool (muscle memory); cobra subcommands for the
inherited UX.

```
httpoc [run] <request> [-c COLLECTION] [-e ENV] [-v K=V]...
       [-n|--dry-run] [-i|--include] [-k|--insecure] [-L|--follow]
       [-H HEADER] [-q QUERY] [--dqwnp[=Q1,Q2]] [--no-interactive]
       [--auth-no-cache]
httpoc list [-c COLLECTION]
httpoc show -c COLLECTION <request>
httpoc version
```

Preserved behaviors: `--dqwnp` without value = all optional queries; interactive =
fzf if installed, else embedded picker, else numbered menu; `--no-interactive`
without a request name = error; interactive selections print the summary with
"Comando equivalente".

## 9. Configuration

`~/.config/httpoc/config.yaml` (created on first run):

```yaml
collections:
  - ~/dev/github.com/Sanmoo/my_api_collections/football-data-opencollection
cache_dir: ~/.cache/httpoc      # OAuth tokens
```

One-shot legacy migration: if `~/.config/.httprc` or `~/.bruwrapper.yaml` exist,
first run imports their `collections:` roots and prints what it did (never
silent, never destructive).

## 10. Error Handling and Exit Codes

- `0` — request completed (any HTTP status; curl semantics — no fail on 4xx/5xx)
- `1` — fatal errors (missing config, collection/request not found, invalid YAML)
- `2` — usage errors (bad flag, `-v` without `=`, `--no-interactive` without request)
- `130` — SIGINT
- Messages: `error: ...` to stderr, `warning: ...` to stderr (parity with Python)

## 11. Quality Gateway (local execution)

Solo dev: no CI server. The gateway is a **local protocol executed by AI agents**,
with the Makefile as the only entry point and evidence (command output) required
before any commit or completion claim. Documented in `docs/quality-gate.md`.

### Coverage — 100%, with explicit exclusion list

Tool: `go-test-coverage` with `coverage.yaml` versioned:

```yaml
threshold: { file: 100, package: 100, total: 100 }
exclude:
  paths:
    - ^cmd/httpoc/main\.go$   # composition root; exercised by the e2e binary
  functions:
    - ^main$                  # execution glue; no logic
```

Policy: every exclusion requires a justification comment in the YAML; the list
starts with at most those two entries and does not grow without discussion.
Everything else — including the interactive selector (via the `io.Reader` seam
and a fake `fzf` on PATH) — is tested.

### Mutation testing — gremlins

- PR scope: `internal/core` + `internal/app` (pure, fast unit tests)
- Full repo (adapters incl. httptest): on-demand `make mutate-full`
- Gate: **mutation score ≥85%** on core/app; ≥80% on the full run
  (equivalent mutants exist, so 100% mutation score is not a realistic target)

### Static analysis — golangci-lint, numeric gates (all `issues: error`)

| Indicator | Tool | Limit |
|---|---|---|
| Cyclomatic complexity | gocyclo | ≤ 10 per function |
| Cognitive complexity | gocognit | ≤ 15 per function |
| Function length | funlen | ≤ 60 lines |
| Duplication | dupl | ≤ 100 tokens |
| Bugs/vet | govet, staticcheck, errcheck, errorlint, bodyclose | 0 |
| Security | gosec, govulncheck | 0 |
| Style | gofmt, goimports, revive, misspell, unconvert, wastedassign | 0 |

### Makefile targets

```
make check          # full pipeline: lint → test -race → coverage → mutate → parity → vuln
make lint           # golangci-lint
make test           # go test ./... -race
make coverage       # go test -coverprofile + go-test-coverage (100%, exclusion list)
make mutate         # gremlins core/app (≥85%)
make mutate-full    # whole repo (≥80%), on demand
make parity         # golden files vs Python baseline
make vuln           # govulncheck
make build / make release   # cross-compile (linux/macos × amd64/arm64)
```

Agent protocol (in `docs/quality-gate.md`): full `make check` green is a
precondition for commits and completion claims; agent pastes relevant output as
evidence; the exclusion list only changes with justification.

## 12. Test Plan

Three layers, all runnable offline:

**Layer 1 — Unit tests** (fast, majority): templating (`{{var}}`,
`{{process.env.X}}`), variable precedence, path-params → variables, auth
inheritance, optional-query selection, cache-key derivation, YAML parsing of
fixtures, discovery walk, request-name resolution, equivalent-curl builder
(quoting, bearer masking, `-k/-L/-i`), URL building (encodeUrl, disabled params,
optional queries), token cache (expiry boundary now+60, corrupt file, 0600),
config load/migration, formatter (valid pretty JSON, raw passthrough on non-TTY).

**Layer 2 — Integration tests** (`httptest`, no external network): method,
headers, query, body (raw + form-urlencoded), content-type; redirects
(on/off/max); TLS insecure (`-k` vs self-signed); timeout; streaming of large
bodies; `-i`; OAuth2 end-to-end (fake token server + protected API: 401 → fetch
token → retry with Authorization); transport errors → exit codes.

**Layer 3 — CLI e2e** (binary built in test, fixture collections in tempdir):
**golden files for `--dry-run`** — outputs captured from the Python tool today as
baseline; Go must match byte-for-byte (the parity gate). Each scenario of
`tests/http-oc-test.sh` (~30 scenarios) becomes a table-driven Go test + golden.
`list`/`show` output; exit codes per error class (0/1/2/130). Interactive: no PTY
in v1 — selector via seam, numbered-menu fallback via piped stdin.

## 13. Migration and Deprecation

1. Create `httpoc` repo; **quality gateway first** (Makefile, coverage.yaml,
   .golangci.yml, docs/quality-gate.md) — safety net before product code.
2. Migrate reusable adapters from `bruno-wrapper` (jsonhighlight, formatter,
   fzf selector, cobra cmd pattern).
3. Capture **golden baseline**: run Python `http oc -n` over the
   `http-oc-test.sh` scenarios; freeze outputs in `testdata/golden/`.
4. Port the `run` use case (core + app + adapters) with tests in parallel
   (TDD; each .sh scenario → Go test).
5. Port `list`/`show`/`version`.
6. **Parity gate**: goldens green + manual smoke on real collections
   (football-data, seguros-unimed, java_learning) → `httpoc` is canonical.
7. Deprecation: `bruno-wrapper` README points to `httpoc`; `oc` subcommand
   removed from the Python `http` (REST client stays); `http-oc-test.sh`
   retired, `http-test.sh` remains.
8. Repo public; dormant Actions workflow available.

## 14. Success Criteria

- `make check` is green on a fresh clone (all gates: lint, race tests, 100%
  coverage with ≤2 exclusions, mutation ≥85% core/app, parity goldens, vuln).
- Every scenario in `tests/http-oc-test.sh` has a corresponding Go test; dry-run
  goldens match the Python baseline byte-for-byte.
- Manual smoke passes on the user's real collections.
- `httpoc` runs with neither `curl` nor `fzf` installed (standalone proof).
- `go install github.com/sanmoo/httpoc@latest` works; release binaries build
  for linux/darwin × amd64/arm64.
- `bruno-wrapper` README deprecated; Python `http` keeps its REST client without
  the `oc` subcommand.
