# httpoc public-readiness: README rewrite, examples, comment cleanup, CI visibility

Date: 2026-08-03 · Status: approved (4 design sections, user)

## Context & Goal

The `httpoc` repo is about to go public. Its README still references the
owner's private tooling ("the `oc` subcommand of the Python `http` tool",
`bruno-wrapper` as predecessor) and personal real-world collections
(`football-data`, `seguros-unimed`) in config examples. Goal: make the repo
presentable to strangers — self-contained, reproducible, no private context —
without changing tool behavior.

## Decisions (user rulings)

1. **Scope: README + code comments** (not just README). Tests are not
   rewritten (their `.httprc`/`.bruwrapper.yaml` references are real feature
   behavior).
2. **Legacy migration feature stays, documented generically** — one sentence
   in the README: "On first run, imports collection roots from the
   predecessor tool's config files (`~/.config/.httprc`,
   `~/.bruwrapper.yaml`) — read, never modified".
3. **Quick start must be reproducible**: a committed example collection
   (`examples/petstore`, moved from the test fixtures — single source of
   truth) + an inline YAML snippet in the README educating readers on the
   OpenCollection 1.0.0 request shape.
4. **CI activated on push** (workflow already mirrors `make check` 1:1) with a
   status badge; the local `make check` protocol remains the official gate.

## README structure (12 sections)

1. What it is — 2-3 self-contained sentences: standalone HTTP CLI for
   OpenCollection 1.0.0 collections; one-shot requests, discovery, variables,
   OAuth2, curl-equivalent dry-run; single static binary, no curl/fzf/Python
   at runtime. No predecessor mention.
2. Features — current list, de-personalized.
3. Install — unchanged (`go install` + 4 release binaries).
4. Quick start — clone → config `collections: [./examples]` (note: run from
   repo root) → `list` → `show` → dry-run (`-n`, no network) → note that real
   execution hits the `baseUrl` hosts, point them at your own API.
5. Collection format — trimmed `opencollection.yaml` + full `get-pet.yaml`.
6. Command reference — current tables, unchanged.
7. Configuration — config.yaml, environments, generic migration clause.
8. Exit codes — current table, unchanged.
9. Quality gate — local protocol official; CI badge; "CI mirrors the same
   gate on every push".
10. Development — make targets + layout, unchanged.
11. Roadmap — current, de-personalized.
12. License — MIT.

## examples/petstore

- `git mv testdata/collections/spec/petstore examples/petstore` (manifest +
  4 requests; dummy creds, public-safe). `testdata/collections/spec/` is
  removed (empty).
- Test helpers updated: `petstorePath()` (e2e_test.go) → `examples/petstore`;
  `specRoot()` (catalog_test.go) → `examples` root. Behavior unchanged.

## Comment normalization rule

Replace (private names/paths): `http oc` → "the original Python tool" (or
drop); `dotfiles/general/bin/http` → drop; `bruno-wrapper` → "the deprecated
predecessor" (or drop); real collection names in test comments → generic.
Keep: "Python" provenance, module path, `.httprc`/`.bruwrapper.yaml` feature
names, pinned parity string literals. Files (~15): main.go, formatter.go,
jsonhighlight.go(+test), runner.go, curl.go, selector.go, catalog.go,
show.go, list.go, run.go, resolve.go, e2e_test.go, app_test.go,
parity_test.go, capture-goldens.sh.

## CI

- `.github/workflows/ci.yml`: no changes (push trigger, mirrors make check).
- README §9: `[![ci](https://github.com/sanmoo/httpoc/actions/workflows/ci.yml/badge.svg)]` badge + mirror wording.
- `docs/quality-gate.md`: "no CI server" line → "local protocol enforced by AI
  agents; the GitHub Actions pipeline mirrors the same gate on push".
- Badge is dead until the repo exists publicly — accepted.

## Verification

- `make check` ALL GREEN after all changes (comment-only edits cannot break
  behavior; helper path updates are exercised by the existing e2e/catalog
  tests).
- README quick-start commands verified by running them against the moved
  example (dry-run only).

## Out of scope

Screenshot/demo GIF, extra badges (license/Go version), contributing/security
docs, creating the public repo itself (user action, after this work).
