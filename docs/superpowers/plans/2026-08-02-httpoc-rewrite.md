# httpoc — Go Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the `http oc` OpenCollection CLI in Go as a standalone single binary (`httpoc`), spec-aligned to OpenCollection 1.0.0, with behavioral parity, a local quality gateway (100% coverage, mutation testing, static analysis gates), and deprecation of `bruno-wrapper` and the Python `oc` subcommand.

**Architecture:** Hexagonal (mirroring `bruno-wrapper`): `internal/core` (pure domain + ports), `internal/app` (use cases), `internal/adapters` (catalog, runner, auth, terminal, interactive, config), `cmd/httpoc` (cobra wiring). Spec: `docs/superpowers/specs/2026-08-02-httpoc-rewrite-design.md` (commit `32d606b` in the dotfiles repo).

**Tech Stack:** Go 1.26 (mise-installed at `~/.local/share/mise/installs/go/1.26.3/bin`), cobra (`github.com/spf13/cobra`), `gopkg.in/yaml.v3`, `golang.org/x/term`, `golang.org/x/oauth2` (only if needed — flows are simple form POSTs; prefer manual port for byte-parity), golangci-lint 2.12.2 (mise), go-test-coverage, gremlins, govulncheck.

**Repo:** `~/dev/github.com/Sanmoo/httpoc` (new; module `github.com/sanmoo/httpoc`). Reference files live in the dotfiles repo (`~/dev/github.com/Sanmoo/dotfiles`): `general/bin/http` (Python source of truth for parity), `tests/http-oc-test.sh` (33 scenarios), `general/bin/auth-code-token` (auth code flow reference).

## Global Constraints

Every task implicitly includes all of these:

- **Coverage gate**: `go test -coverprofile=cover.out ./...` + `go-test-coverage --config=coverage.yaml`; thresholds file/package/total = 100. Exclusions allowed ONLY via `coverage.yaml` (initially `^cmd/httpoc/main\.go$` path and `^main$` function); any addition needs a justification comment and user approval.
- **Mutation gate**: `gremlins unleash` on `internal/core` + `internal/app`: score ≥85%. Full repo: ≥80% (`make mutate-full`).
- **Lint gates** (all `issues: error`): gocyclo ≤10, gocognit ≤15, funlen ≤60, dupl ≤100 tokens, govet/staticcheck/errcheck/errorlint/bodyclose 0 findings, gosec 0, gofmt/goimports/revive/misspell/unconvert/wastedassign 0.
- **Exit codes**: 0 = request completed (any HTTP status); 1 = fatal (config/collection/request missing, invalid YAML); 2 = usage errors; 130 = SIGINT. Messages `error: ...` / `warning: ...` on stderr.
- **Format**: OpenCollection 1.0.0 spec keys ONLY (`info.type: http` + `http:` block, `accessTokenUrl`, `flow:`, `credentials.clientId`, `settings.followRedirects`...). No legacy `request:` blocks, no `.bru`.
- **No external runtime deps**: no curl, fzf, bru, or Python at runtime.
- **TDD**: every code step writes the failing test first, verifies it fails, implements minimally, verifies it passes.
- **Every task ends with**: `make check` green (evidence pasted into the task log) + `git commit`.
- Spec schema reference: `~/dev/github.com/Sanmoo/` sibling clone at `/tmp/pi-github-repos/opencollection-dev/opencollection/packages/oc-schema/src/opencollection.schema.json` (re-clone if missing).

---

### Task 1: Repo scaffold + quality gateway working

**Files:**

- Create: `~/dev/github.com/Sanmoo/httpoc/go.mod`, `Makefile`, `.golangci.yml`, `coverage.yaml`, `.gitignore`, `LICENSE`, `README.md`, `docs/quality-gate.md`, `.github/workflows/ci.yml`, `cmd/httpoc/main.go` (stub), `.git/` (git init)

**Interfaces:**

- Produces: the `make check` pipeline (lint → test -race → coverage → mutate → parity → vuln) that every later task must pass; `coverage.yaml` exclusion list; `docs/quality-gate.md` agent protocol.

- [ ] **Step 1: Create the repo and module**

```bash
mkdir -p ~/dev/github.com/Sanmoo/httpoc
cd ~/dev/github.com/Sanmoo/httpoc
git init -b main
go mod init github.com/sanmoo/httpoc
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
/dist/
/cover.out
*.test
.DS_Store
```

- [ ] **Step 3: Write `coverage.yaml`** (the exclusion list — the contract)

```yaml
profile: cover.out
local-prefix: github.com/sanmoo/httpoc
threshold:
  file: 100
  package: 100
  total: 100
exclude:
  paths:
    - ^cmd/httpoc/main\.go$   # composition root; exercised by e2e binary tests
  functions:
    - ^main$                  # execution glue; no logic
```

- [ ] **Step 4: Write `.golangci.yml`** (numeric gates — all issues are errors)

```yaml
version: "2"
run:
  timeout: 5m
linters:
  default: none
  enable:
    - errcheck
    - govet
    - staticcheck
    - gocritic
    - revive
    - gocyclo
    - gocognit
    - funlen
    - dupl
    - gosec
    - misspell
    - unconvert
    - wastedassign
    - whitespace
    - bodyclose
    - errorlint
    - gofmt
    - goimports
    - ineffassign
    - unused
  settings:
    gocyclo:
      min-complexity: 11        # fail at >10
    gocognit:
      min-complexity: 16        # fail at >15
    funlen:
      lines: 60
      statements: 40
    dupl:
      threshold: 100
    revive:
      rules:
        - name: package-comments
          disabled: true
issues:
  max-issues-per-linter: 0
  max-same-issues: 0
```

- [ ] **Step 5: Write the `Makefile`** (the quality gateway entry point)

<!-- markdownlint-disable MD010 -->

```make
GO ?= go
GOLANGCI ?= golangci-lint
PKGS := ./...

.PHONY: check lint test coverage mutate mutate-full parity vuln build release

check: lint test coverage mutate parity vuln
	@echo "QUALITY GATEWAY: ALL GREEN"

lint:
	$(GOLANGCI) run ./...

test:
	$(GO) test -race -count=1 ./...

coverage:
	$(GO) test -coverprofile=cover.out $(PKGS)
	$(GO) run github.com/vladopajic/go-test-coverage@latest --config=coverage.yaml

mutate:
	$(GO) run github.com/go-gremlins/gremlins/cmd/gremlins@latest unleash \
		--pkg ./internal/core/...,./internal/app/... --workers=4 --fail

mutate-full:
	$(GO) run github.com/go-gremlins/gremlins/cmd/gremlins@latest unleash \
		--workers=4 --fail

parity:
	$(GO) test -count=1 -run 'TestParity|TestE2E' ./...

vuln:
	$(GO) run golang.org/x/vuln/cmd/govulncheck@latest ./...

build:
	mkdir -p dist
	$(GO) build -o dist/httpoc ./cmd/httpoc

release:
	mkdir -p dist
	GOOS=linux GOARCH=amd64 $(GO) build -o dist/httpoc-linux-amd64 ./cmd/httpoc
	GOOS=linux GOARCH=arm64 $(GO) build -o dist/httpoc-linux-arm64 ./cmd/httpoc
	GOOS=darwin GOARCH=amd64 $(GO) build -o dist/httpoc-darwin-amd64 ./cmd/httpoc
	GOOS=darwin GOARCH=arm64 $(GO) build -o dist/httpoc-darwin-arm64 ./cmd/httpoc
```

<!-- markdownlint-enable MD010 -->

- [ ] **Step 6: Write the stub `main.go`** (replaced in Task 11; excluded from coverage)

```go
package main

import "fmt"

func main() {
 fmt.Println("httpoc: not implemented yet")
}
```

- [ ] **Step 7: Write `docs/quality-gate.md`** (the agent protocol)

```markdown
# Quality Gate

Local protocol enforced by AI agents (no CI server).

1. `make check` green is a precondition for any commit and any completion claim.
2. Agents paste relevant command output as evidence (coverage report, mutation
   score, lint summary, parity diff).
3. The `coverage.yaml` exclusion list changes only with a justification comment
   and user approval.
4. Each gate has exactly one Makefile target — partial runs are not evidence.
```

- [ ] **Step 8: Write dormant `LICENSE` (MIT)** — copyright `2026 Sanmoo`, standard MIT text.

- [ ] **Step 9: Write dormant `.github/workflows/ci.yml`** — same pipeline as the Makefile, `on: workflow_dispatch` and `on: push` (documented in README as dormant; nothing depends on it).

- [ ] **Step 10: Write `README.md` stub** — project name, one-line description, "quality gate: `make check`", link to `docs/quality-gate.md`. Full docs land in Task 13.

- [ ] **Step 11: Verify the gateway runs on the empty repo**

Run: `make check`
Expected: lint passes (stub main is trivially clean), tests pass, coverage 100% (only excluded main.go exists), mutation reports 0 mutants, vuln clean. If `gremlins` or `go-test-coverage` fail on an empty module, fix the Makefile invocation (e.g. add `--dry-run` handling) — the contract is the targets, not the tool flags.

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "chore: scaffold httpoc repo with local quality gateway"
```

---

### Task 2: Test fixtures (legacy + spec) and golden baseline

**Files:**

- Create: `testdata/collections/legacy/collectionA/opencollection.yaml`, `testdata/collections/legacy/collectionA/requests/get-smart-conditions.yaml` (+ every fixture the 33 `.sh` scenarios need: fallbackCollection, badCollection, requests with body/auth/params), `testdata/collections/spec/` (spec-shaped collection: manifest + requests with `info.type: http` + `http:` blocks, environments, variables, optional queries, oauth2 CC auth), `scripts/capture-goldens.sh`, `testdata/golden/` (captured outputs)

**Interfaces:**

- Produces: `testdata/collections/legacy/*` — fixtures the Python tool CAN run (parity axis A, goldens); `testdata/collections/spec/*` — spec-shaped fixtures the Go tool targets (axis B, no Python baseline; expectations authored from the spec); `scripts/capture-goldens.sh` — reproduces goldens from the Python tool; `testdata/golden/<scenario>.golden` — byte-parity contract for Task 7/12.

- [ ] **Step 1: Port the legacy fixtures from `tests/http-oc-test.sh`**

Read `~/dev/github.com/Sanmoo/dotfiles/tests/http-oc-test.sh` and extract every fixture it writes (collectionA with `config.environments.development` + `variables`, fallbackCollection without `info.name`, badCollection with a non-mapping manifest, the auth/body/params collections from tests 12-33). Write them verbatim into `testdata/collections/legacy/...` with the same YAML content (the `.sh` writes them at runtime; we freeze them as files).

- [ ] **Step 2: Write the spec-shaped fixture collection**

`testdata/collections/spec/petstore/opencollection.yaml`:

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
request:
  auth:
    type: oauth2
    flow: client_credentials
    accessTokenUrl: https://token.example.com/oauth/token
    credentials:
      clientId: collection-client
      clientSecret: collection-secret
    scope: read
```

`testdata/collections/spec/petstore/requests/get-pet.yaml`:

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
  timeout: 0
  followRedirects: true
  maxRedirects: 5
```

Plus `list-pets.yaml` (query param `limit` with an empty value + optional-query exercise), `create-pet.yaml` (POST + `body: {type: json, data: '{"name":"{{petName}}"}'}`), `delete-pet.yaml` (path param only). All keys must match the official schema defs (`HttpRequest`, `HttpRequestParam`, `RawBody`, `HttpRequestSettings` — verify against the schema file if unsure).

- [ ] **Step 3: Write `scripts/capture-goldens.sh`**

```bash
#!/usr/bin/env bash
# Captures dry-run stdout baselines from the Python `http oc` (parity axis A).
set -euo pipefail
DOTFILES=~/dev/github.com/Sanmoo/dotfiles
HTTP="$DOTFILES/general/bin/http"
FIXTURES="$(cd "$(dirname "$0")/.." && pwd)/testdata/collections/legacy"
GOLDEN="$(cd "$(dirname "$0")/.." && pwd)/testdata/golden"
PYTHONPATH="$HOME/.local/lib/python3.14/site-packages"
export PYTHONPATH

capture() { # name, args...
  local name="$1"; shift
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/home/.config"
  printf 'collections:\n  - %s\n' "$FIXTURES" > "$tmp/home/.config/.httprc"
  HOME="$tmp/home" "$HTTP" oc --no-interactive "$@" > "$GOLDEN/$name.golden" 2>/dev/null || true
  rm -rf "$tmp"
}

mkdir -p "$GOLDEN"
capture basic-dry-run        -c collectionA -e development -n get-smart-conditions
capture cli-vars-override    -c collectionA -e development -v "customerId=cli-customer,defaultHeader=cli-header" -n get-smart-conditions
# One capture per scenario in the .sh suite that runs with -n and asserts on
# stdout. Check each of the 33 tests: capture iff it invokes run_http_oc with
# -n AND asserts on $OC_STDOUT (skip pure exit-code/error-message scenarios).
# Naming: <kebab-case-name> matching the .sh test description.
```

Then run it: `bash scripts/capture-goldens.sh` and verify the goldens are non-empty and contain the expected curl lines (e.g. `https://dev.example.com/smart-conditions/env-customer`).

- [ ] **Step 4: Verify axis-B fixtures parse against the official schema**

Run a one-off check with the official validator if node/npm available:

```bash
cd /tmp/pi-github-repos/opencollection-dev/opencollection
npm ci --prefix packages/oc-schema >/dev/null 2>&1 || true
node -e '
const Ajv = require("ajv");
const { OpenCollectionSchema } = require("./packages/oc-schema");
const fs = require("fs");
const ajv = new Ajv({ allErrors: true });
const validate = ajv.compile(OpenCollectionSchema);
for (const f of ["petstore/opencollection.yaml"]) {
  // YAML->JSON via a tiny parse (or use the yaml package if present)
}
'
```

If the toolchain is not available, skip (the Go catalog tests in Task 5 are the validator); do NOT add a node dependency to the repo.

- [ ] **Step 5: Commit**

```bash
git add testdata scripts
git commit -m "test: add legacy+spec fixtures and golden baseline for parity"
```

---

### Task 3: Core domain model + ports + auth resolution

**Files:**

- Create: `internal/core/model.go`, `internal/core/model_test.go`, `internal/core/ports.go`

**Interfaces:**

- Produces (later tasks consume these exact names):
  - `type Collection struct { Name, Path string; Manifest *Manifest }`
  - `type Manifest struct { Version string; Info Info; Variables []Variable; RequestDefaults *Auth; Config CollectionConfig }`
  - `type Request struct { Name string; Seq int; Path string; HTTP HTTPDetails; Auth *Auth; Settings RequestSettings }` (Auth = top-level `auth:` key)
  - `type HTTPDetails struct { Method, URL string; Headers, Params []Param; Body *Body; Auth *Auth }`
  - `type Param struct { Name, Value, Type string; Disabled bool }`
  - `type Body struct { Type string; Data string; Fields []Param }` (raw: Type+Data; form-urlencoded: Type+Fields)
  - `type Auth struct { Type string; Flow string; AccessTokenURL, AuthorizationURL, CallbackURL string; ClientID, ClientSecret, Scope string; PKCE PKCE; State string }`
  - `type PKCE struct { Disabled bool; Method string }`
  - `type Environment struct { Name string; Variables []Variable }`
  - `type Variable struct { Name, Value string; Disabled bool }`
  - `type RequestSettings struct { EncodeURL bool; Timeout int; FollowRedirects bool; MaxRedirects int }`
  - `func ResolveAuth(r *Request, m *Manifest) *Auth` — http.auth → top-level auth → manifest request.auth → nil
  - `func ValidateAuth(a *Auth) error` — nil ok; Type != "oauth2" → error; Flow not in {client_credentials, authorization_code} → error
  - Ports (in `ports.go`, with `context.Context` in method signatures):
    - `type RunOptions struct { Timeout time.Duration; FollowRedirects bool; MaxRedirects int; Insecure bool; Include bool; Token string }`
    - `type CachedToken struct { AccessToken, TokenType string; ExpiresAt float64 }`
    - `type AuthSpec struct { CollectionPath, EnvironmentName string; Auth *Auth }`
    - `type Catalog interface { DiscoverCollections(ctx context.Context, roots []string) ([]Collection, error); Requests(ctx context.Context, c Collection) ([]Request, error); Environments(ctx context.Context, c Collection) ([]Environment, error) }`
    - `type Runner interface { Run(ctx context.Context, req *http.Request, opts RunOptions) (int, error) }` (stdlib `net/http`; streams body to Stdout)
    - `type AuthProvider interface { Token(ctx context.Context, spec AuthSpec, forceRefresh bool) (string, error) }`
    - `type TokenCache interface { Get(key string) (*CachedToken, error); Set(key string, tok *CachedToken) error }`
    - `type Selector interface { Choose(items []string, label string) (int, error) }`
    - `type Formatter interface { Response(body []byte, tty bool); Summary(collection, env, request, curlLine string, vars map[string]string) }`
    - Note: `Request`/`HTTPDetails` live in `model.go`; ports reference them, no import cycle (`http` is stdlib).

- [ ] **Step 1: Write the failing tests** (`model_test.go`)

```go
package core

import "testing"

func TestResolveAuthPrecedence(t *testing.T) {
 collectionAuth := &Auth{Type: "oauth2", Flow: "client_credentials"}
 requestAuth := &Auth{Type: "oauth2", Flow: "authorization_code"}
 httpAuth := &Auth{Type: "basic"}

 // http.auth wins over top-level auth
 r := &Request{HTTP: HTTPDetails{Auth: httpAuth}, Auth: requestAuth}
 if got := ResolveAuth(r, &Manifest{RequestDefaults: collectionAuth}); got != httpAuth {
  t.Fatalf("expected http.auth to win, got %+v", got)
 }
 // top-level auth wins over collection defaults
 r = &Request{Auth: requestAuth}
 if got := ResolveAuth(r, &Manifest{RequestDefaults: collectionAuth}); got != requestAuth {
  t.Fatalf("expected top-level auth to win, got %+v", got)
 }
 // collection defaults when request has none
 if got := ResolveAuth(&Request{}, &Manifest{RequestDefaults: collectionAuth}); got != collectionAuth {
  t.Fatalf("expected collection defaults, got %+v", got)
 }
 // nil when nothing declares auth
 if got := ResolveAuth(&Request{}, &Manifest{}); got != nil {
  t.Fatalf("expected nil, got %+v", got)
 }
}

func TestValidateAuth(t *testing.T) {
 cases := []struct {
  name string
  auth *Auth
  want bool // true = error expected
 }{
  {"nil is valid", nil, false},
  {"oauth2 client_credentials", &Auth{Type: "oauth2", Flow: "client_credentials"}, false},
  {"oauth2 authorization_code", &Auth{Type: "oauth2", Flow: "authorization_code"}, false},
  {"unsupported type", &Auth{Type: "basic"}, true},
  {"unsupported flow", &Auth{Type: "oauth2", Flow: "implicit"}, true},
 }
 for _, tc := range cases {
  t.Run(tc.name, func(t *testing.T) {
   err := ValidateAuth(tc.auth)
   if (err != nil) != tc.want {
    t.Fatalf("ValidateAuth(%+v) err=%v, want error=%v", tc.auth, err, tc.want)
   }
  })
 }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test ./internal/core/ -run 'TestResolveAuthPrecedence|TestValidateAuth'`
Expected: FAIL — undefined `ResolveAuth`/`ValidateAuth`/`Auth`.

- [ ] **Step 3: Implement `model.go`** — the structs above (YAML tags matching spec keys: `opencollection`, `info`, `http`, `params`, `body`, `auth`, `settings`, `config`, `environments`, `variables`, `flow`, `accessTokenUrl`, `authorizationUrl`, `callbackUrl`, `credentials`, `clientId`, `clientSecret`, `scope`, `pkce`, `encodeUrl`, `timeout`, `followRedirects`, `maxRedirects`) plus `ResolveAuth` (3-level precedence) and `ValidateAuth` (ported from Python `validate_supported_oc_auth`, spec names: `type` + `flow`).

- [ ] **Step 4: Write `ports.go`** — the six interfaces from design §6, with `context.Context` in signatures.

- [ ] **Step 5: Run tests to verify they pass**

Run: `go test ./internal/core/ -count=1`
Expected: PASS.

- [ ] **Step 6: Run the gateway and commit**

Run: `make check`
Expected: green (coverage 100% on the new package — both test files cover all struct construction sites; add any missing table cases until 100%).
Then:

```bash
git add internal/core
git commit -m "feat(core): domain model, ports, auth inheritance and validation"
```

---

### Task 4: Templating, variable resolution, optional queries (`internal/app/resolve.go`)

**Files:**

- Create: `internal/app/resolve.go`, `internal/app/resolve_test.go`

**Interfaces:**

- Consumes: `core.Param`, `core.Request`, `core.Environment`, `core.Variable`
- Produces:
  - `func ExpandTemplate(text string, vars map[string]string, lookupEnv func(string) string, warn func(format string, args ...any)) string`
  - `func MergeVariables(cli, env, requestVars, collectionVars map[string]string) map[string]string` (precedence: cli > env > request > collection)
  - `func PathParamsToVariables(params []core.Param, vars map[string]string, expand func(string, map[string]string) string) map[string]string`
  - `func ParseOptionalQuerySelection(raw []string) (all bool, names map[string]bool)`
  - `func DisabledQueryIndexes(request core.Request, all bool, names map[string]bool, vars map[string]string) map[int]bool`
  - `func CollectMissingVariables(request core.Request, vars map[string]string) []string`
  - `func VariablesFromEnvironment(env *core.Environment) map[string]string`

- [ ] **Step 1: Write the failing tests** — port the relevant `.sh` scenarios as table tests:

Test 1 (env vars in URL/headers + collection vars), test 6 (CLI overrides env + comma-separated `-v`), test 10 (missing variable → collected), test 11 (disabled placeholders ignored), test 14 (missing vars in path params and body fail early), test 9 (ambiguous names — that's catalog/CLI, skip here), plus template specifics:

```go
package app

import (
 "fmt"
 "testing"
)

func TestExpandTemplate(t *testing.T) {
 vars := map[string]string{"baseUrl": "https://dev.example.com", "customerId": "env-customer"}
 env := func(string) string { return "" }
 var warnings []string
 warn := func(format string, args ...any) { warnings = append(warnings, fmt.Sprintf(format, args...)) }

 got := ExpandTemplate("{{baseUrl}}/smart-conditions/{{customerId}}", vars, env, warn)
 if got != "https://dev.example.com/smart-conditions/env-customer" {
  t.Fatalf("got %q", got)
 }
 // process.env expands from lookupEnv and warns when empty
 env = func(k string) string { return "from-env" }
 got = ExpandTemplate("{{process.env.TOKEN}}", vars, env, warn)
 if got != "from-env" {
  t.Fatalf("process.env got %q", got)
 }
 // unknown variables are left as-is? NO — Python leaves them and
 // CollectMissingVariables reports them; the template keeps the raw text.
 got = ExpandTemplate("{{missing}}", vars, env, warn)
 if got != "{{missing}}" {
  t.Fatalf("unknown var got %q, want raw placeholder", got)
 }
}

func TestMergeVariablesPrecedence(t *testing.T) {
 merged := MergeVariables(
  map[string]string{"k": "cli"},
  map[string]string{"k": "env", "onlyEnv": "e"},
  map[string]string{"k": "req", "onlyReq": "r"},
  map[string]string{"k": "col", "onlyCol": "c"},
 )
 if merged["k"] != "cli" || merged["onlyEnv"] != "e" || merged["onlyReq"] != "r" || merged["onlyCol"] != "c" {
  t.Fatalf("precedence broken: %v", merged)
 }
}

func TestParseOptionalQuerySelection(t *testing.T) {
 all, names := ParseOptionalQuerySelection(nil)
 if all || names != nil {
  t.Fatalf("nil input: all=%v names=%v", all, names)
 }
 all, names = ParseOptionalQuerySelection([]string{"__HTTP_OC_ALL_QUERIES__"})
 if !all || len(names) != 0 {
  t.Fatalf("sentinel: all=%v names=%v", all, names)
 }
 all, names = ParseOptionalQuerySelection([]string{"limit,offset", "page"})
 if all || !names["limit"] || !names["offset"] || !names["page"] {
  t.Fatalf("names: all=%v names=%v", all, names)
 }
}
```

- [ ] **Step 2: Run tests to verify they fail** — undefined functions.
- [ ] **Step 3: Implement `resolve.go`** — port from Python `apply_template`/`expand_process_env` (regex `\{\{([^{}]+)\}\}`; first pass `{{process.env.X}}` with warning when empty; second pass named vars; values expanded recursively), `parse_oc_vars`, `variables_list_to_dict`, `add_path_params_to_variables`, `parse_optional_query_selection`, `resolve_optional_queries` (param disabled when its variable is unset and it is in the requested names, or all=true and var unset — match Python `optional_query_is_covered` exactly), `collect_missing_variables`.
- [ ] **Step 4: Run tests to verify they pass** — plus table cases for `DisabledQueryIndexes` and `CollectMissingVariables` mirroring .sh tests 10/11/14 (write them in Step 1's file if not already — the failing-first cycle applies per behavior; add now and run).
- [ ] **Step 5: Gateway + commit**

Run: `make check` — green, coverage 100% on `internal/app`.
Commit: `feat(app): variable resolution, templating, optional queries`.

---

### Task 5: Catalog adapter (spec-shaped parsing + discovery)

**Files:**

- Create: `internal/adapters/catalog/catalog.go`, `catalog_test.go`

**Interfaces:**

- Consumes: `core.*` model, `testdata/collections/spec/`
- Produces: `type Catalog struct { Roots []string }` implementing `core.Catalog`:
  - `DiscoverCollections(ctx, roots) ([]core.Collection, error)` — walk roots recursively; a directory containing `opencollection.yaml|opencollection.yml|collection.yaml|collection.yml` is a collection; stop descending after a manifest (Python prunes `dirs`); name = `info.name` else dir name; non-mapping manifest → error `collection manifest must be a YAML mapping: <path>` (parity message).
  - `Requests(ctx, c) ([]core.Request, error)` — walk collection dir; files `.yaml/.yml` excluding manifests; parse; keep docs with `info.type == "http"` or an `http:` block; name = `info.name` else file stem; sorted by name.
  - `Environments(ctx, c) ([]core.Environment, error)` — from `config.environments` (list of `{name, variables}`), spec `Environment` shape; non-mapping manifest handled above.

- [ ] **Step 1: Write failing tests** using the spec fixture (`testdata/collections/spec`):

```go
package catalog

import (
 "context"
 "path/filepath"
 "runtime"
 "testing"

 "github.com/sanmoo/httpoc/internal/core"
)

func specRoot(t *testing.T) string {
 t.Helper()
 _, file, _, _ := runtime.Caller(0)
 return filepath.Join(filepath.Dir(file), "..", "..", "..", "testdata", "collections", "spec")
}

func TestDiscoverCollections(t *testing.T) {
 c := &Catalog{Roots: []string{specRoot(t)}}
 ctx := context.Background()
 cols, err := c.DiscoverCollections(ctx, c.Roots)
 if err != nil {
  t.Fatal(err)
 }
 if len(cols) != 1 || cols[0].Name != "petstore" {
  t.Fatalf("collections: %+v", cols)
 }
}

func TestRequests(t *testing.T) {
 // ... assert 4 requests discovered: get-pet, list-pets, create-pet, delete-pet
 // assert get-pet.Name == "get-pet", HTTP.Method == "GET",
 // HTTP.URL == "{{baseUrl}}/pets/{{petId}}",
 // HTTP.Params[0] == {verbose, "true", query, false},
 // Settings.FollowRedirects == true, Settings.MaxRedirects == 5
}

func TestEnvironments(t *testing.T) {
 // ... assert development env with baseUrl + petId variables
}
```

- [ ] **Step 2: Run to verify fail** — undefined `Catalog`.
- [ ] **Step 3: Implement** — `gopkg.in/yaml.v3` (`go get gopkg.in/yaml.v3`); a `manifest` struct with spec YAML tags; `isManifest(name)`; `isRequestDoc(data)` (mirror Python `is_http_request_doc` but spec keys); request struct with `info`/`http`/`settings` tags; error wrapping with the offending path (parity: errors mention the file path).
- [ ] **Step 4: Run to verify pass** — add cases: bad manifest (list instead of mapping) → error contains path and `must be a YAML mapping`; a non-HTTP doc (e.g. a `docs:` markdown file) is skipped; name fallback to file stem when `info.name` missing.
- [ ] **Step 5: Gateway + commit** — `make check` green; commit `feat(catalog): spec-shaped OpenCollection parsing and discovery`.

---

### Task 6: Runner adapter (net/http execution)

**Files:**

- Create: `internal/adapters/runner/runner.go`, `runner_test.go`

**Interfaces:**

- Consumes: `core.Request`, `core.RequestSettings`, resolved vars (map)
- Produces:
  - `type Runner struct { Stdout io.Writer; Stderr io.Writer }` implementing `core.Runner` — `RunOptions` is defined in `core` (Task 3); this package consumes it (`core.RunOptions`).
  - `func BuildRequest(r core.Request, vars map[string]string, opts core.RunOptions) (*http.Request, error)` — method (default GET), URL with `{{var}}` expanded (Task 4) and path params substituted, query params (type `query`, skip disabled; `encodeUrl` true → url.QueryEscape values; false → raw), headers (skip disabled; name/value expanded), body (raw: `Body.Data` as-is with Content-Type from `Body.Type` mapping json→application/json, xml→application/xml, text→text/plain, sparql→application/sparql-query; form-urlencoded: `Body.Fields` url.Values), Authorization header when Token != "".
  - `Run(ctx, req, opts) (int, error)` — executes with `http.Client` (Timeout, CheckRedirect honoring FollowRedirects/MaxRedirects, Transport with `TLSClientConfig.InsecureSkipVerify` when Insecure); writes response status+headers to Stdout when Include (curl `-i` semantics), then streams body to Stdout; returns HTTP status code; transport errors → wrapped error.

- [ ] **Step 1: Write failing tests** (integration, `httptest`):

```go
package runner

import (
 "bytes"
 "context"
 "net/http"
 "net/http/httptest"
 "testing"
 "time"

 "github.com/sanmoo/httpoc/internal/core"
)

func TestRunStreamsBodyAndReturnsStatus(t *testing.T) {
 srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
  if r.Method != "POST" {
   t.Errorf("method: %s", r.Method)
  }
  if got := r.Header.Get("X-Default"); got != "from-collection" {
   t.Errorf("header: %q", got)
  }
  if got := r.URL.Query().Get("verbose"); got != "true" {
   t.Errorf("query: %q", got)
  }
  w.Header().Set("Content-Type", "application/json")
  w.WriteHeader(201)
  _, _ = w.Write([]byte(`{"ok":true}`))
 }))
 defer srv.Close()

 var out bytes.Buffer
 r := &Runner{Stdout: &out, Stderr: &bytes.Buffer{}}
 req, err := BuildRequest(core.Request{
  HTTP: core.HTTPDetails{
   Method: "POST",
   URL:    srv.URL + "/pets",
   Headers: []core.Param{{Name: "X-Default", Value: "from-collection"}},
   Params:  []core.Param{{Name: "verbose", Value: "true", Type: "query"}},
   Body:    &core.Body{Type: "json", Data: `{"name":"rex"}`},
  },
 }, map[string]string{}, RunOptions{})
 if err != nil {
  t.Fatal(err)
 }
 status, err := r.Run(context.Background(), req, RunOptions{})
 if err != nil {
  t.Fatal(err)
 }
 if status != 201 {
  t.Fatalf("status: %d", status)
 }
 if out.String() != `{"ok":true}` {
  t.Fatalf("body: %q", out.String())
 }
}
```

Plus: redirects (follow on → 200 at final URL; follow off → 302 status), maxRedirects cap → error, insecure against `httptest.NewTLSServer` with `Insecure: true` (and failure without), timeout (server that sleeps 200ms, Timeout 50ms → error), include (`-i`) prints `HTTP/1.1 200 OK` + headers before body, form-urlencoded body → `Content-Type: application/x-www-form-urlencoded` + parsed form values, content-type mapping for xml/text/sparql, disabled params/headers skipped.

- [ ] **Step 2: Run to verify fail** — undefined `Runner`/`BuildRequest`.
- [ ] **Step 3: Implement** — `go get golang.org/x/net` not needed; stdlib only. Redirect policy: `CheckRedirect` returns `http.ErrUseLastResponse` when FollowRedirects false; cap redirects at MaxRedirects (default 5) via counting. Insecure: per-call Transport (clone DefaultTransport, set TLSClientConfig).
- [ ] **Step 4: Run to verify pass** — iterate until all cases green; add missing cases for full file coverage (e.g. BuildRequest with empty method, encodeUrl false).
- [ ] **Step 5: Gateway + commit** — `make check` green (note: coverage 100% on runner requires the TLS/timeout/redirect cases to run — they do); commit `feat(runner): net/http execution with settings, TLS, redirects, streaming`.

---

### Task 7: Equivalent-curl builder (byte-parity with Python)

**Files:**

- Create: `internal/adapters/runner/curl.go`, `curl_test.go`

**Interfaces:**

- Consumes: the goldens from Task 2 (`testdata/golden/*.golden`)
- Produces:
  - `func CurlArgs(method, url string, headers []string, queries []string, body string, include, insecure, follow bool, token string) []string`
  - `func ShellQuote(s string) string` — byte-parity port of Python `shlex.quote`
  - `func FormatCurlCommand(args []string) string` — `"curl " + strings.Join(quoted, " ")`
  - `func MaskBearerToken(line string) string`

- [ ] **Step 1: Write the failing tests** — golden byte-parity + unit edge cases:

```go
package runner

import (
 "os"
 "path/filepath"
 "runtime"
 "strings"
 "testing"
)

func goldenDir(t *testing.T) string {
 t.Helper()
 _, file, _, _ := runtime.Caller(0)
 return filepath.Join(filepath.Dir(file), "..", "..", "..", "testdata", "golden")
}

func TestCurlArgsParityWithPythonBaseline(t *testing.T) {
 // The .golden files were captured from the Python tool (Task 2).
 // Each golden line is a full `curl ...` command; feed it through the
 // same input the Python saw (scenario args) and compare byte-for-byte.
 // Scenario: basic-dry-run == `http oc --no-interactive -c collectionA
 // -e development -n get-smart-conditions` on the legacy fixture.
 //
 // The legacy fixture URL is {{baseUrl}}/smart-conditions/{{customerId}}
 // with env baseUrl=https://dev.example.com customerId=env-customer and
 // headers Accept + X-Default(from-collection).
 got := FormatCurlCommand(CurlArgs(
  "get",
  "https://dev.example.com/smart-conditions/env-customer",
  []string{"Accept: application/json", "X-Default: from-collection"},
  nil, "", false, false, false, "",
 ))
 want, err := os.ReadFile(filepath.Join(goldenDir(t), "basic-dry-run.golden"))
 if err != nil {
  t.Fatal(err)
 }
 if strings.TrimRight(got, "\n") != strings.TrimRight(string(want), "\n") {
  t.Fatalf("parity mismatch:\n got: %s\nwant: %s", got, want)
 }
}

func TestShellQuote(t *testing.T) {
 cases := map[string]string{
  "":            "''",
  "plain":       "plain",
  "with space":  "'with space'",
  "a'b":         `'a'"'"'b'`,
  "https://x.y": "https://x.y", // ':' '/' '.' are safe in shlex
  "v=1&w=2":     "'v=1&w=2'",
 }
 for in, want := range cases {
  if got := ShellQuote(in); got != want {
   t.Errorf("ShellQuote(%q) = %s, want %s", in, got, want)
  }
 }
}

func TestMaskBearerToken(t *testing.T) {
 line := "curl --silent --show-error -H 'Authorization: Bearer abc123' 'https://api/x'"
 want := "curl --silent --show-error -H 'Authorization: Bearer ***' 'https://api/x'"
 if got := MaskBearerToken(line); got != want {
  t.Fatalf("got %s", got)
 }
 // token must NOT swallow the closing quote (Python lookahead parity)
 if strings.Contains(MaskBearerToken(line), "***'") {
  t.Fatal("masking swallowed the closing quote")
 }
}
```

- [ ] **Step 2: Run to verify fail** — undefined functions.
- [ ] **Step 3: Implement `curl.go`** — exact port of Python `build_curl_args` + `format_curl_command` + `mask_bearer_token`:
  - args start `["--silent", "--show-error"]`; `-X METHOD.upper()` when method != "get"; `-i`/`-k`/`-L` when flags; `-H header` per header; `-H "Authorization: Bearer <token>"` when token; auto Content-Type header from body type (json/xml/text/sparql mapping — explicit headers win); URL + `?k=v` with `url.QueryEscape(v)` (matches Python `quote_plus` for this purpose); `--data body` when body != "".
  - `ShellQuote`: port of `shlex.quote` — empty → `''`; if all runes are alnum or in `@%+=:,./-` → as-is; else wrap in `'` with embedded `'` replaced by `'"'"'`.
  - `MaskBearerToken`: `regexp.MustCompile(`(Authorization: Bearer )[^\s']+`)` → `${1}***` (Go RE2 has no lookahead; `[^\s']+` matches Python's `\S+?(?=\s|')` exactly).
- [ ] **Step 4: Run to verify pass** — byte-parity on every golden scenario (add one table case per golden file; generate the input args from the fixture, mirroring the capture script).
- [ ] **Step 5: Gateway + commit** — `make check` green; commit `feat(runner): equivalent-curl builder with byte parity`.

---

### Task 8: Auth adapter (OAuth2 + token cache)

**Files:**

- Create: `internal/adapters/auth/cache.go`, `internal/adapters/auth/oauth.go`, `internal/adapters/auth/auth_test.go`

**Interfaces:**

- Consumes: `core.Auth`, config cache dir
- Produces:
  - `func CacheKey(collectionPath, envName string, a *core.Auth) string` — `sha256(path + "\x00" + envName + "\x00" + flow + "\x00" + accessTokenURL + "\x00" + clientID + "\x00" + scope)` hex + `.json` (parity with Python `cache_key_for_auth`)
  - `Token(ctx context.Context, spec core.AuthSpec, forceRefresh bool) (string, error)` — implements `core.AuthProvider`; `spec.Auth` nil → return "", nil (no auth)
  - `type Cache struct { Dir string }` implementing `core.TokenCache`:
    - `Get(key) (*CachedToken, error)` — nil when missing, corrupt, or `expires_at <= now+60` (Python `load_cached_token`)
    - `Set(key, tok) error` — JSON `{access_token, token_type, expires_at}` written 0600, atomic (temp file + rename)
  - `type CachedToken struct { AccessToken, TokenType string; ExpiresAt float64 }`
  - `type Provider struct { Cache core.TokenCache; OpenBrowser func(url string) error; Listen func(network, addr string) (net.Listener, error); Stdout, Stderr io.Writer }` implementing `core.AuthProvider` (see `Token` signature above):
    - `Token` behavior — template-expand auth string fields first (parity, via Task 4 `ExpandTemplate`); cache hit unless force (cache key via `CacheKey(spec.CollectionPath, spec.EnvironmentName, spec.Auth)`); CC → POST `accessTokenUrl` with form `grant_type=client_credentials&client_id=...&client_secret=...&scope=...` (scope only when set), Content-Type `application/x-www-form-urlencoded`; AC → PKCE flow (below); save + return `access_token`.
  - AC flow (port of `general/bin/auth-code-token`): PKCE S256 (verifier: 43-128 char random, challenge: base64url-no-pad of sha256(verifier)); state: random hex; loopback server `127.0.0.1:8765/callback` (or `callbackUrl` override) capturing ONE GET with `?code=&state=`; open browser to `authorizationUrl?response_type=code&client_id=...&redirect_uri=...&state=...&code_challenge=...&code_challenge_method=S256&scope=...` (+ `prompt=login` when forceRefresh); exchange: POST `accessTokenUrl` form `grant_type=authorization_code&code=...&redirect_uri=...&client_id=...&code_verifier=...`; PKCE disabled when `pkce.disabled`.

- [ ] **Step 1: Write failing tests**:

Cache unit tests (no network): key stability + distinct inputs → distinct keys; Get on missing file → nil; corrupt JSON → nil; expired (`expires_at` in past and within now+60) → nil; valid → token; Set creates dir, 0600 perms, JSON roundtrip; atomic (no partial file on crash — assert temp+rename by checking no `*.tmp` leftovers).

```go
package auth

import (
 "os"
 "path/filepath"
 "testing"
 "time"

 "github.com/sanmoo/httpoc/internal/core"
)

func TestCacheKeyParity(t *testing.T) {
 a := &core.Auth{Flow: "client_credentials", AccessTokenURL: "https://t.example/x", ClientID: "cid", Scope: "read"}
 k1 := CacheKey("/collections/a", "development", a)
 k2 := CacheKey("/collections/b", "development", a)
 if k1 == k2 {
  t.Fatal("distinct collections must differ")
 }
 if len(k1) != 65 || filepath.Ext(k1) != ".json" { // 64 hex + .json
  t.Fatalf("key shape: %q", k1)
 }
 // stability
 if CacheKey("/collections/a", "development", a) != k1 {
  t.Fatal("key must be deterministic")
 }
}

func TestCacheExpiryBoundary(t *testing.T) {
 dir := t.TempDir()
 c := &Cache{Dir: dir}
 key := "k.json"
 if err := c.Set(key, &CachedToken{AccessToken: "tok", TokenType: "Bearer", ExpiresAt: float64(time.Now().Unix()) + 120}); err != nil {
  t.Fatal(err)
 }
 if tok, err := c.Get(key); err != nil || tok == nil || tok.AccessToken != "tok" {
  t.Fatalf("valid token: %+v err=%v", tok, err)
 }
 // within the 60s grace window → treated as expired
 if err := c.Set(key, &CachedToken{AccessToken: "tok", ExpiresAt: float64(time.Now().Unix()) + 30}); err != nil {
  t.Fatal(err)
 }
 if tok, _ := c.Get(key); tok != nil {
  t.Fatal("token within grace window must be expired")
 }
}
```

OAuth integration (httptest): CC happy path (fake token server asserts form fields, returns `{"access_token":"t1","expires_in":3600}`; provider returns t1 and caches it; second call without force returns t1 without hitting the server — assert via request counter); force refresh hits the server again; CC server error → error mentions `client_credentials`; AC happy path with a fake authorization server + fake browser (OpenBrowser captures the URL; the "browser" fetches it, the fake auth endpoint redirects to callback with code+state) + fake token server; AC with `forceRefresh` adds `prompt=login` to the authorization URL; token cache persists across Provider instances (same Dir).

- [ ] **Step 2: Run to verify fail**.
- [ ] **Step 3: Implement** — `cache.go` + `oauth.go` as specified. Use `crypto/sha256`, `crypto/rand`, `encoding/base64`, `net`, `net/http` (stdlib); no oauth2 dependency needed (the flows are two form POSTs — keep zero deps beyond yaml/cobra/term).
- [ ] **Step 4: Run to verify pass** — iterate; cover `Token` with nil auth (returns "", nil — no auth), unsupported flow (error via `core.ValidateAuth`).
- [ ] **Step 5: Gateway + commit** — `make check` green; commit `feat(auth): oauth2 client credentials + authorization code with PKCE and token cache`.

---

### Task 9: Config adapter

**Files:**

- Create: `internal/adapters/config/config.go`, `config_test.go`

**Interfaces:**

- Produces:
  - `type Config struct { Path string; Collections []string; CacheDir string }`
  - `func Load(home string) (*Config, error)` — reads `~/.config/httpoc/config.yaml`; missing file → error `~/.config/httpoc/config.yaml not found; expected YAML with a collections: list` (message parity with Python test 2, new path); non-mapping → error `must be a YAML mapping`; default `CacheDir = ~/.cache/httpoc`.
  - `func CreateDefault(home string, roots []string) (*Config, error)` — writes config with the given roots, 0600, prints `created ~/.config/httpoc/config.yaml with N collection root(s)` to stderr.
  - `func MigrateLegacy(home string) (*Config, error)` — when the config file is absent: if `~/.config/.httprc` OR `~/.bruwrapper.yaml` exist with a `collections:` list, import those roots via `CreateDefault`, print `imported N collection root(s) from <path>` to stderr; never modifies the legacy file.

- [ ] **Step 1: Write failing tests**:

```go
package config

import (
 "os"
 "path/filepath"
 "strings"
 "testing"
)

func TestLoadMissing(t *testing.T) {
 home := t.TempDir()
 _, err := Load(home)
 if err == nil || !strings.Contains(err.Error(), ".config/httpoc/config.yaml") {
  t.Fatalf("missing config error: %v", err)
 }
}

func TestLoadInvalidShape(t *testing.T) {
 home := t.TempDir()
 dir := filepath.Join(home, ".config", "httpoc")
 if err := os.MkdirAll(dir, 0o755); err != nil {
  t.Fatal(err)
 }
 if err := os.WriteFile(filepath.Join(dir, "config.yaml"), []byte("- not-a-mapping\n"), 0o600); err != nil {
  t.Fatal(err)
 }
 _, err := Load(home)
 if err == nil || !strings.Contains(err.Error(), "must be a YAML mapping") {
  t.Fatalf("invalid shape error: %v", err)
 }
}

func TestLoadDefaultsAndValues(t *testing.T) {
 home := t.TempDir()
 dir := filepath.Join(home, ".config", "httpoc")
 _ = os.MkdirAll(dir, 0o755)
 _ = os.WriteFile(filepath.Join(dir, "config.yaml"),
  []byte("collections:\n  - /tmp/collections\ncache_dir: /tmp/cache\n"), 0o600)
 cfg, err := Load(home)
 if err != nil {
  t.Fatal(err)
 }
 if len(cfg.Collections) != 1 || cfg.Collections[0] != "/tmp/collections" || cfg.CacheDir != "/tmp/cache" {
  t.Fatalf("config: %+v", cfg)
 }
 // default cache dir when unset
 _ = os.WriteFile(filepath.Join(dir, "config.yaml"), []byte("collections:\n  - /tmp/collections\n"), 0o600)
 cfg, _ = Load(home)
 if cfg.CacheDir == "" || !strings.Contains(cfg.CacheDir, ".cache") {
  t.Fatalf("default cache dir: %+v", cfg)
 }
}

func TestMigrateLegacyHttprc(t *testing.T) {
 home := t.TempDir()
 cfgDir := filepath.Join(home, ".config")
 _ = os.MkdirAll(cfgDir, 0o755)
 _ = os.WriteFile(filepath.Join(cfgDir, ".httprc"),
  []byte("collections:\n  - /old/root\n"), 0o600)
 cfg, err := MigrateLegacy(home)
 if err != nil {
  t.Fatal(err)
 }
 if len(cfg.Collections) != 1 || cfg.Collections[0] != "/old/root" {
  t.Fatalf("migrated: %+v", cfg)
 }
 if _, err := os.Stat(filepath.Join(cfgDir, ".httprc")); err != nil {
  t.Fatal("legacy file must not be deleted")
 }
}
```

- [ ] **Step 2: Run to verify fail**.
- [ ] **Step 3: Implement** — yaml.v3; paths via `filepath.Join(home, ".config", "httpoc", "config.yaml")`; `CreateDefault` mkdir 0755 + write 0600; `MigrateLegacy` checks `.httprc` then `.bruwrapper.yaml` (both: YAML mapping with `collections:` list; if both exist, merge dedup).
- [ ] **Step 4: Run to verify pass** — add: migrate from `.bruwrapper.yaml`; both files → merged; neither → returns `Load` error; `CreateDefault` writes 0600 + prints.
- [ ] **Step 5: Gateway + commit** — `make check` green; commit `feat(config): httpoc config with one-shot legacy migration`.

---

### Task 10: Terminal + interactive adapters

**Files:**

- Create: `internal/adapters/terminal/formatter.go`, `formatter_test.go`, `internal/adapters/interactive/selector.go`, `selector_test.go`; migrate `internal/adapters/terminal/jsonhighlight.go` from `~/dev/github.com/Sanmoo/bruno-wrapper/internal/adapters/terminal/`

**Interfaces:**

- Consumes: `core.Collection`, `core.Request`, resolved vars
- Produces:
  - `type Formatter struct { Stdout, Stderr io.Writer }` implementing `core.Formatter` (signatures from Task 3):
    - `Response(body []byte, tty bool)` — tty: pretty-print JSON (migrated jsonhighlight) + trailing newline; non-tty: raw bytes (curl parity)
    - `Summary(collection, env, request, curlLine string, vars map[string]string)` — the interactive summary block + `Comando equivalente: <masked>` (masked via Task 7's `MaskBearerToken`)
  - `type Selector struct { In io.Reader; Out, ErrOut io.Writer; FZF string }` (`FZF` = path to fzf binary, "" = not available) implementing `core.Selector`
    - `Choose(items []string, label string) (int, error)` — resolution order: fzf available → exec `FZF` with items on stdin (migrated from bruno-wrapper `selector.go`; input escape-safe: read selected line from stdout, match by exact line); else numbered menu on ErrOut + `ReadString` on In (parity with Python `choose_with_fzf_or_prompt` fallback: `label number:` prompt, 1-based); empty items → error `no <label> choices available` (parity).
  - **Scoping note (recorded):** the embedded fuzzy picker (design §6) is deferred to v1.1 — a raw-mode TUI needs PTY testing, which the design explicitly excludes from v1 (`no PTY`). v1 selector = fzf (when installed) + numbered menu, exactly the Python behavior.

- [ ] **Step 1: Write failing tests**:

```go
package interactive

import (
 "bytes"
 "path/filepath"
 "runtime"
 "strings"
 "testing"
)

func TestChooseNumberedMenu(t *testing.T) {
 in := strings.NewReader("2\n")
 var errOut bytes.Buffer
 s := &Selector{In: in, ErrOut: &errOut}
 idx, err := s.Choose([]string{"alpha", "beta", "gamma"}, "request")
 if err != nil || idx != 1 {
  t.Fatalf("idx=%d err=%v", idx, err)
 }
 if !strings.Contains(errOut.String(), "Choose request:") {
  t.Fatalf("prompt missing: %q", errOut.String())
 }
}

func TestChooseEmpty(t *testing.T) {
 s := &Selector{In: strings.NewReader(""), ErrOut: &bytes.Buffer{}}
 if _, err := s.Choose(nil, "request"); err == nil || !strings.Contains(err.Error(), "no request choices available") {
  t.Fatalf("empty error: %v", err)
 }
}

func TestChooseFZF(t *testing.T) {
 _, file, _, _ := runtime.Caller(0)
 fake := filepath.Join(filepath.Dir(file), "testdata", "fake-fzf")
 s := &Selector{In: strings.NewReader(""), ErrOut: &bytes.Buffer{}, FZF: fake}
 idx, err := s.Choose([]string{"alpha", "beta"}, "request")
 if err != nil || idx != 1 {
  t.Fatalf("fzf idx=%d err=%v", idx, err)
 }
}
```

Plus formatter tests: pretty JSON output is valid JSON with indentation on tty; raw passthrough on non-tty; `Summary` masks tokens and includes `Comando equivalente:`.

- [ ] **Step 2: Run to verify fail**.
- [ ] **Step 3: Implement + migrate** — copy `jsonhighlight.go` from bruno-wrapper (same package layout; adapt imports); write `selector.go` (numbered menu + fzf exec; fzf detection = `exec.LookPath("fzf")` at construction in the wiring layer, or explicit `FZF` field); create `testdata/fake-fzf` fixture:

```bash
#!/usr/bin/env bash
# Fake fzf: echoes the last line it received (tests select deterministically).
tail -n 1
```

(chmod +x; committed.)

- [ ] **Step 4: Run to verify pass** — add: invalid menu input (non-numeric → error), out-of-range number → error, fzf missing binary → falls back to menu.
- [ ] **Step 5: Gateway + commit** — `make check` green; commit `feat(terminal): formatter + fzf/numbered-menu selector (jsonhighlight migrated)`.

---

### Task 11: App use cases + cobra CLI + e2e tests

**Files:**

- Create: `internal/app/run.go`, `internal/app/list.go`, `internal/app/show.go`, `internal/app/app_test.go`, `cmd/httpoc/main.go` (replace stub), `cmd/httpoc/root.go`, `cmd/httpoc/run.go`, `cmd/httpoc/list.go`, `cmd/httpoc/show.go`, `cmd/httpoc/version.go`, `internal/app/e2e_test.go`

**Interfaces:**

- Consumes: everything from Tasks 3-10.
- Produces:
  - `type Deps struct { Catalog core.Catalog; Runner core.Runner; Auth core.AuthProvider; Selector core.Selector; Formatter core.Formatter; Stdout, Stderr io.Writer; Home string }` (the `TokenCache` is wired into the auth `Provider` at the composition root in `cmd/`, not here)
  - `func Run(ctx, deps Deps, args RunArgs) int` — the orchestration from design §7; returns the process exit code (0/1/2/130).
  - `type RunArgs struct { RequestName, Collection, Environment string; Vars []string; DryRun, Include, Insecure, Follow, NoInteractive, AuthNoCache bool; Headers, Queries []string; DQWNP []string }`
  - `func List(ctx, deps Deps, collection string) int`, `func Show(ctx, deps Deps, collection, request string) int`
  - cobra commands binding the same flags as the Python tool (flag names from design §8; `--dqwnp` with `NoOptDefVal: "all"` + custom `normalize` for the `__HTTP_OC_ALL_QUERIES__` sentinel parity).

**Run() flow (parity with Python `main_oc`):**

1. `config.Load(deps.Home)` — error → stderr `error: ...` + return 1 (missing config) / 2 (bad shape) — Python uses 2 for `die()`; keep parity: config errors → 2.
2. `Catalog.DiscoverCollections`; select via `-c` name match (exact; ambiguous → error listing matches; missing → error listing available) or `Selector` when interactive.
3. `Catalog.Requests`; select by name or stem (ambiguous handling parity), error `request name is required in --no-interactive mode` → 2.
4. `Catalog.Environments`; `-e` match (ambiguous/missing → die), none → nil, one → it, multiple + interactive → Selector, multiple + non-interactive → `environment is required when multiple environments exist; pass -e/--environment` → 2.
5. Resolve vars (Task 4): CLI `-v` (comma-separated `K=V`, error → 2), env, request, collection; `{{process.env.X}}` via `os.LookupEnv`; path params → vars; optional queries: `--dqwnp` parse + validate names against request params (unknown name → error listing valid, parity test 9/11), interactive prompt `enable optional queries?` when params exist and no selection (parity `prompt_enable_optional_queries`).
6. Missing variables: interactive → prompt each (stderr prompt + stdin read, parity `prompt_missing_variables`), non-interactive → error listing them → 2.
7. Auth: `core.ResolveAuth` + `core.ValidateAuth` (unsupported → 2, parity test 17); `AuthProvider.Token` with template-expanded auth fields; token → `Authorization: Bearer` header.
8. `runner.BuildRequest` + `runner.Run` — but dry-run: build the equivalent curl via Task 7 and print masked line to Stdout, return 0 (parity: `-n` never executes).
9. Interactive-used summary: if any Selector/prompt was used, print `Summary` including `Comando equivalente:` (masked) — including after Ctrl-C (parity `finally` clause), return 130 on SIGINT (context cancel → 130).
10. Errors from Runner (transport) → stderr `error: ...` + return 1.

**cobra wiring:** root command name `httpoc`; when the first positional arg is not a known subcommand, treat it as `run <request>` (cobra `RunE` on root + `Args: ArbitraryArgs`); flags bound identically to Python; `version` prints `httpoc <version>` from `debug.ReadBuildInfo`.

**E2E tests** (`e2e_test.go`, build once per test run):

- `TestE2EExitCodes`: build binary to `t.TempDir()`; run with `HOME=<tmp>` + fixture legacy/spec collections in config; assert: dry-run exit 0 + output == golden (reuse goldens for the full pipeline — this is the real parity test); missing config → 2 + stderr mentions path; unknown request → 2 + lists available; missing request name non-interactive → 2; bad flag → 2; SIGINT simulation → skip (no PTY in v1).
- `TestE2EListShow`: `list` prints collections + requests; `show` prints method/URL/headers with masked token.
- `TestE2ENumberedMenu`: pipe `2\n` into stdin, run without request name, HOME with one collection containing 3 requests → runs the 2nd.

- [ ] **Step 1: Write the failing e2e tests** (they define the contract; unit tests for Run() come alongside).
- [ ] **Step 2: Run to verify fail**.
- [ ] **Step 3: Implement `internal/app/run.go`** (orchestration; keep it ≤60 lines per function — the lint gate is watching; extract helpers: `selectCollection`, `selectRequest`, `selectEnvironment`, `resolveAll`).
- [ ] **Step 4: Implement `list.go`/`show.go`** (list: `Collections:` / `Requests:` blocks, `GET <name>` lines — parity with bruno-wrapper output shape; show: `Method:/URL:/Headers:` block, masked values).
- [ ] **Step 5: Implement cobra commands + replace `cmd/httpoc/main.go`** (keep it a thin wiring-only file — it is excluded from coverage).
- [ ] **Step 6: Run all tests to verify pass** — iterate; add unit tests for Run() error mapping (fake deps, table-driven) until `internal/app` is 100% covered (e2e covers the binary; unit covers the branches).
- [ ] **Step 7: Gateway + commit** — `make check` green (full: lint, race, coverage 100%, mutation ≥85% on core+app, parity, vuln); commit `feat(cli): run/list/show commands with parity orchestration`.

---

### Task 12: Full parity suite + `make parity` gate

**Files:**

- Create: `internal/app/parity_test.go` (or extend `e2e_test.go`), table-driven port of ALL 33 scenarios from `tests/http-oc-test.sh`

**Interfaces:**

- Consumes: legacy fixtures (axis A) + spec fixtures (axis B) + goldens.
- Produces: the complete parity contract — every `.sh` scenario has a Go equivalent that runs against the compiled binary with `HOME` in a temp dir.

- [ ] **Step 1: Inventory the 33 scenarios**

Read `~/dev/github.com/Sanmoo/dotfiles/tests/http-oc-test.sh` end-to-end and build the scenario table:

```go
var parityScenarios = []struct {
 name      string
 args      []string
 fixture   string // legacy | spec
 wantExit  int
 wantOut   []string // substrings that must appear in stdout
 wantErr   []string // substrings that must appear in stderr
 golden    string   // optional golden file for byte equality
}{
 {"basic dry-run", []string{"--no-interactive", "-c", "collectionA", "-e", "development", "-n", "get-smart-conditions"}, "legacy", 0, []string{"https://dev.example.com/smart-conditions/env-customer", "Accept: application/json", "X-Default: from-collection"}, nil, "basic-dry-run.golden"},
 {"missing rc", []string{"--no-interactive", "-c", "collectionA", "-n", "get-smart-conditions"}, "legacy", 2, nil, []string{"config.yaml", "collections"}, ""},
 // One entry per scenario, tests 1-33, in .sh order. Each entry mirrors its
 // .sh test exactly: same args, same exit code, same assert_contains /
 // assert_not_contains substrings (wantOut/wantErr), same golden when the
 // .sh asserts on $OC_STDOUT of a -n run.
}
```

- [ ] **Step 2: Port each scenario** — for axis-B scenarios (spec fixtures) there is no Python baseline: the expected substrings are authored from the spec + the design (e.g. `httpoc --no-interactive -c petstore -e development -n get-pet` → stdout contains the masked curl with `https://dev.example.com/pets/env-pet`; optional-query scenario omits `limit` when unset).
- [ ] **Step 3: Wire `make parity`** — the target already runs `TestParity|TestE2E`; add a `-update` flag handling (goldens regenerate via `go test -run TestParity -update` writing from the current binary — used ONLY when the Python baseline legitimately changes; the default run fails on mismatch).
- [ ] **Step 4: Run the full suite** — `make check`; fix every mismatch by comparing with the Python behavior (run the .sh scenario against Python for ground truth); NO test weakening — mismatches are Go bugs or documented spec-alignment deltas (record each delta in the test comment).
- [ ] **Step 5: Commit** — `test(parity): port all 33 http-oc scenarios to Go table tests`.

---

### Task 13: Smoke on real collections, deprecation, docs

**Files:**

- Modify: `~/dev/github.com/Sanmoo/httpoc/README.md` (full docs), `~/dev/github.com/Sanmoo/bruno-wrapper/README.md` (deprecation note), `~/dev/github.com/Sanmoo/dotfiles/general/bin/http` (remove oc), `~/dev/github.com/Sanmoo/dotfiles/tests/http-oc-test.sh` (delete), `~/dev/github.com/Sanmoo/dotfiles/tests/http-test.sh` (keep, must stay green)

**Interfaces:**

- Consumes: the parity-green binary from Task 12.

- [ ] **Step 1: Manual smoke on real collections** (evidence checklist — paste each output):

```bash
cd ~/dev/github.com/Sanmoo/httpoc
cat > /tmp/smoke-home/.config/httpoc/config.yaml <<EOF
collections:
  - ~/dev/github.com/Sanmoo/my_api_collections/football-data-opencollection
  - ~/dev/github.com/Sanmoo/my_api_collections/seguros-unimed
  - ~/dev/github.com/Sanmoo/my_api_collections/java_learning-opencollection
EOF
go build -o dist/httpoc ./cmd/httpoc
HOME=/tmp/smoke-home ./dist/httpoc list
HOME=/tmp/smoke-home ./dist/httpoc show -c football-data areas
HOME=/tmp/smoke-home ./dist/httpoc -c football-data areas -n          # dry-run, no network
HOME=/tmp/smoke-home ./dist/httpoc -c seguros-unimed reembolsos -n    # dry-run
HOME=/tmp/smoke-home ./dist/httpoc -c java_learning-opencollection <req> -n
```

Verify: every request in each collection is discoverable and dry-runs to a sane curl; `list`/`show` render correctly. Record any spec-shape discovery gap as a Go bug (fix in Task 5 code) — NOT as a fixture change.

- [ ] **Step 1b: Standalone proof (no curl, no fzf on PATH)** — run with an empty PATH; the binary must work without exec-ing anything (dry-run + list + numbered menu via piped stdin):

```bash
cd ~/dev/github.com/Sanmoo/httpoc
env PATH= HOME=/tmp/smoke-home ./dist/httpoc list
env PATH= HOME=/tmp/smoke-home ./dist/httpoc --no-interactive -c football-data areas -n
printf '1\n' | env PATH= HOME=/tmp/smoke-home ./dist/httpoc -c football-data 2>/dev/null || true  # numbered menu, no fzf
```

Expected: all three succeed with empty PATH (Go binary needs no PATH; selector falls back to the numbered menu because `fzf` is not resolvable). This is success criterion §14 "runs with neither curl nor fzf installed".

- [ ] **Step 2: Write the full `README.md`** — what it is (OC 1.0.0 runner), install (`go install github.com/sanmoo/httpoc@latest` + release binaries), quick start (config file, first run, legacy migration), command reference (the §8 surface), exit codes, quality gate pointer, development (make targets), roadmap (assertions/scripts/chaining → later phases).
- [ ] **Step 3: Deprecate `bruno-wrapper`** — prepend a note to its README: deprecated in favor of `httpoc` (link), no new features, kept for existing users.
- [ ] **Step 4: Remove `oc` from the Python `http`** — in `~/dev/github.com/Sanmoo/dotfiles/general/bin/http`, delete the oc-specific code paths (`parse_args` oc branch, `main_oc`, oc parser + helpers, `OC_*` constants) while keeping the REST client intact; run `bash tests/http-test.sh` → must stay green; delete `tests/http-oc-test.sh`.
- [ ] **Step 5: Verify both repos green**

```bash
cd ~/dev/github.com/Sanmoo/httpoc && make check
cd ~/dev/github.com/Sanmoo/dotfiles && bash tests/http-test.sh
```

- [ ] **Step 6: Commit both repos**

```bash
cd ~/dev/github.com/Sanmoo/httpoc && git add -A && git commit -m "docs: README, deprecation note, smoke evidence"
cd ~/dev/github.com/Sanmoo/bruno-wrapper && git add README.md && git commit -m "docs: deprecate in favor of httpoc"
cd ~/dev/github.com/Sanmoo/dotfiles && git add general/bin/http tests && git commit -m "refactor(http): remove oc subcommand, keep REST client"
```

- [ ] **Step 7: Release check** — `make release` builds the 4 binaries; `git tag v0.1.0 && git push --tags` (repo can go public; dormant Actions workflow is ready).

---

## Self-Review Notes

- **Spec coverage**: §4 layout → Tasks 1,3-11; §5 model/inheritance → Task 3; §6 ports → Task 3; §7 flow → Task 11; §8 CLI surface → Task 11; §9 config → Task 9; §10 exit codes → Tasks 11-12; §11 quality gateway → Tasks 1, every task gate; §12 test layers → Tasks 3-10 (unit), 6/8 (integration), 11-12 (e2e/goldens); §13 migration → Tasks 1,2,5,11,12,13; §14 success criteria → Task 12 (scenario parity), Task 13 (smoke, standalone proof, releases).
- **Verified empirically during planning**: the Python tool does NOT discover spec-shaped requests (`no HTTP request YAML files discovered in collection` on `football-data-opencollection`) → axis A (goldens from Python, legacy fixtures) vs axis B (spec fixtures, authored expectations) split in Tasks 2/5/12.
- **Auth code flow** references `general/bin/auth-code-token` (PKCE S256, loopback 8765/callback, state, prompt=login) — ported in Task 8.
- **Spec names** (`accessTokenUrl`, `flow:`, `credentials.clientId`) confirmed against the official schema; the user's real collections carry no OAuth2 yet (only proxy auth), so no legacy aliases are needed (recorded decision #2 stands).
- **Deferred (recorded):** embedded fuzzy picker → v1.1 (needs PTY, excluded from v1); assertions/scripts/chaining/gRPC/GraphQL/WS → later phases per design §2.
