# `http oc` — OpenCollection MVP design

**Date:** 2026-06-24
**Status:** Awaiting user review of written spec
**Scope:** Add an `oc` subcommand to `general/bin/http` that discovers OpenCollection-like collections from `~/.config/.httprc`, resolves requests/environments/variables with an interactive UX, supports OAuth2 client credentials and authorization code, and translates the selected request into the existing curl execution path.

---

## 1. Problem Statement

The existing `general/bin/http` script is useful for one-off REST calls, but it does not help when requests are already organized as API collections. The desired workflow is:

```sh
http oc -c collectionA -e development -v "variableA=valueA,variableB=valueB" get-smart-conditions
```

The tool should avoid forcing the user to browse collection folders and inspect YAML files manually. It should discover collections, requests, environments, and missing variables, then guide the user with `fzf`/prompts when information is missing.

The goal is not full OpenCollection support. The MVP should support a pragmatic subset that is close enough to the spec to evolve later.

---

## 2. Goals and Non-Goals

### Goals

- Add `http oc` without breaking existing `http get/post/put/patch/delete` behavior.
- Read a YAML manifest from `~/.config/.httprc`.
- Discover collections under configured roots by finding collection manifest files.
- Locate request YAML files by basename inside a collection tree.
- Support an OpenCollection-like HTTP request subset.
- Resolve variables from CLI, environment, request, and collection scopes.
- Provide interactive selection/fill-in with `fzf` where possible.
- Provide `--no-interactive` for scripts/CI.
- Support OAuth2 client credentials and authorization code only.
- Cache OAuth2 tokens in `~/.cache/http-oc/` when `expires_in` is available.
- Add a dedicated test file: `tests/http-oc-test.sh`.

### Non-Goals

- No complete OpenCollection schema implementation.
- No GraphQL, gRPC, WebSocket, scripts, assertions, examples, proxy, certificates, or folder-level inheritance in the MVP.
- No OAuth2 resource owner password or implicit flow.
- No bearer/basic/api-key auth as formal auth types; users can model those as headers with variables.
- No hidden/secret prompt handling for sensitive variable names.
- No multipart or file body support in OpenCollection mode.

---

## 3. Command Surface

### Invocation

```sh
http oc [flags] [request-name]
```

Examples:

```sh
http oc -c collectionA -e development -v "variableA=valueA,variableB=valueB" get-smart-conditions
http oc --collection collectionA --environment development --var variableA=valueA get-smart-conditions
http oc
http oc --no-interactive -c collectionA -e development get-smart-conditions
```

### Flags

| Flag | Short | Description |
| --- | --- | --- |
| `--collection NAME` | `-c` | Collection name to use. Matches `info.name` first, then directory name. |
| `--environment NAME` | `-e` | Environment name from the collection manifest. |
| `--var KEY=VALUE` | `-v` | Variable override. Repeatable and also accepts comma-separated pairs. |
| `--no-interactive` | | Disable fzf/prompts; missing/ambiguous values become errors. |
| `--dry-run` | `-n` | Print the resulting curl command instead of executing. Same behavior as existing CLI. |
| `--include` | `-i` | Pass through to curl. |
| `--insecure` | `-k` | Pass through to curl. |
| `--follow` | `-L` | Pass through to curl. |
| `--header` | `-H` | Extra header override, appended after request-derived headers. |
| `--query` | `-q` | Extra query parameter, appended after request-derived params. |

Existing non-`oc` subcommands keep their current flags and behavior.

---

## 4. Manifest and Collection Discovery

### User manifest

The tool reads YAML from:

```text
~/.config/.httprc
```

MVP format:

```yaml
collections:
  - /abc
  - ~/work/api-collections
```

Each entry is a root directory to scan. `~` and environment variables are expanded.

### Collection manifest names

Under each root, the tool discovers collections by looking for directories that contain one of these files, in order:

1. `opencollection.yaml`
2. `opencollection.yml`
3. `collection.yaml`
4. `collection.yml`

The collection display/match name is:

1. `info.name` from the collection manifest, if present
2. otherwise the collection directory basename

If `-c` matches multiple collections, interactive mode opens `fzf`; `--no-interactive` errors and prints the candidates.

---

## 5. Request Discovery

Requests are YAML files anywhere under the selected collection directory. The invocation name is the file basename without `.yaml`/`.yml`:

```text
/abc/collectionA/requests/get-smart-conditions.yaml
```

is invoked as:

```sh
http oc -c collectionA get-smart-conditions
```

A YAML file is considered an HTTP request if it has `type: http` or a compatible `request.method` / `request.url` structure. Collection manifest files themselves are excluded from request discovery.

If no request name is provided, interactive mode lists discovered requests in `fzf`. `--no-interactive` errors.

---

## 6. Supported OpenCollection Subset

### Request YAML

Supported shape:

```yaml
type: http
name: Get Smart Conditions
request:
  method: GET
  url: "{{baseUrl}}/smart-conditions"
  headers:
    - name: Accept
      value: application/json
    - name: X-Customer
      value: "{{customerId}}"
      disabled: false
  params:
    - name: status
      value: active
      type: query
      disabled: false
  body:
    type: json
    data: |
      {"foo":"{{bar}}"}
```

Supported fields:

- `type: http`
- `name`
- `request.method`
- `request.url`
- `request.headers[]` with `name`, `value`, optional `disabled`
- `request.params[]` with `name`, `value`, `type: query|path`, optional `disabled`
- `request.body` raw body with `type: json|text|xml|sparql` and `data`

Disabled headers/params are ignored.

### URL and params

- `request.url` may be absolute and may contain `{{variables}}`.
- Query params from `request.params[]` with `type: query` are appended to the URL.
- Params with `type: path` are treated as variables by adding each param `name`/`value` to the variable map before template substitution. The MVP supports `{{name}}` placeholders; single-brace `{name}` placeholders are out of scope.

### Body

The MVP supports raw inline body only:

```yaml
request:
  body:
    type: json
    data: '{"x":"{{value}}"}'
```

Content-Type is added if absent:

| Body type | Header |
| --- | --- |
| `json` | `Content-Type: application/json` |
| `xml` | `Content-Type: application/xml` |
| `text` | `Content-Type: text/plain` |
| `sparql` | `Content-Type: application/sparql-query` |

Explicit request or CLI `Content-Type` wins.

---

## 7. Environments and Variables

### Environments

Collection manifest environments use the OpenCollection-like config shape:

```yaml
config:
  environments:
    - name: development
      variables:
        - name: baseUrl
          value: https://dev.example.com
        - name: customerId
          value: "123"
```

Selection rules:

- `-e NAME` selects that environment.
- If `-e` is omitted and there is one environment, use it automatically.
- If `-e` is omitted and there are multiple environments, use `fzf` in interactive mode.
- If `-e` is omitted in `--no-interactive` and the choice is ambiguous, error.
- If there are no environments, continue without one.

### Variable sources

Variables are accepted from:

- CLI `-v KEY=VALUE`
- CLI comma-separated `-v "a=b,c=d"`
- selected environment variables
- request-level variables
- collection-level variables

Supported variable shapes:

```yaml
variables:
  - name: foo
    value: bar
```

and:

```yaml
request:
  variables:
    - name: foo
      value: bar
```

### Precedence

Highest to lowest:

1. CLI `-v` / `--var`
2. selected environment
3. request variables
4. collection variables
5. interactive prompt for missing variables
6. error if `--no-interactive`

Template syntax remains `{{name}}`.

---

## 8. OAuth2 Support and Cache

Only `oauth2` auth is interpreted by `http oc`. Other auth mechanisms should be expressed as regular headers with variables.

### Auth location and inheritance

Supported sources:

1. request-level `auth`
2. collection request defaults: `request.auth`
3. no auth

Folder-level inheritance is out of scope for the MVP.

### Client credentials

Expected shape:

```yaml
auth:
  type: oauth2
  grantType: client_credentials
  tokenUrl: "{{tokenUrl}}"
  clientId: "{{clientId}}"
  clientSecret: "{{clientSecret}}"
  scope: "{{scope}}"
```

The implementation may call the existing `general/bin/client-credentials-token` when compatible, or use equivalent `curl`/`jq` subprocess logic. The resulting access token is sent as:

```text
Authorization: Bearer <token>
```

### Authorization code

Expected shape:

```yaml
auth:
  type: oauth2
  grantType: authorization_code
  authorizationUrl: "{{authorizationUrl}}"
  tokenUrl: "{{tokenUrl}}"
  clientId: "{{clientId}}"
  scope: openid profile
  redirectUri: http://127.0.0.1:8765/callback
```

The implementation should reuse `general/bin/auth-code-token` because it already handles PKCE, browser opening, and callback capture.

### Token cache

Cache directory:

```text
~/.cache/http-oc/
```

Cache key is derived from:

- collection path
- environment name
- grant type
- token URL
- client ID
- scope

If the token response includes `expires_in`, cache:

```json
{
  "access_token": "...",
  "token_type": "Bearer",
  "expires_at": 1780000000
}
```

Reuse cached token if `expires_at` is still valid with a 60-second safety margin. If `expires_in` is missing, do not cache.

---

## 9. Interactive UX

The default is interactive when stdin/stdout are TTYs and `--no-interactive` is not set.

Interactive behavior:

- Missing `-c`: open `fzf` with discovered collections.
- Missing request name: open `fzf` with discovered requests.
- Missing `-e` with multiple environments: open `fzf`.
- Missing variable values: prompt with normal echoed input:

  ```text
  value for customerId:
  ```

- If any interactive selection or prompt was used, print a concise summary before execution:

  ```text
  Collection: collectionA
  Environment: development
  Request: get-smart-conditions
  GET https://dev.example.com/smart-conditions
  ```

`fzf` is optional. If a picker is required but `fzf` is unavailable, fallback to a numbered textual prompt when interactive. In `--no-interactive`, error.

---

## 10. Error Handling

Tool errors print to stderr and exit 2.

Important errors:

| Condition | Behavior |
| --- | --- |
| `~/.config/.httprc` missing | Error explaining expected file and `collections:` key. |
| invalid YAML | Error with file path. |
| no collections discovered | Error listing scanned roots. |
| `-c` not found | Error with available collection names. |
| ambiguous `-c` in non-interactive mode | Error with candidate paths. |
| request not found | Error with available request names. |
| missing request in non-interactive mode | Error asking for request name. |
| ambiguous/missing environment in non-interactive mode | Error asking for `-e`. |
| missing variable in non-interactive mode | Error listing missing variable names. |
| unsupported request body/auth/grant | Error saying unsupported by MVP. |
| OAuth script/token failure | Propagate useful stderr/context. |

Curl failures propagate curl's exit code.

---

## 11. Architecture

The existing direct subcommands stay as they are. New code is grouped into helper functions inside `general/bin/http` initially; if the file grows too large during implementation, focused extraction can be considered later.

Suggested helpers:

- `parse_oc_args(...)`
- `load_httprc(path)`
- `discover_collections(roots)`
- `select_collection(...)`
- `load_collection_manifest(collection)`
- `discover_requests(collection_path)`
- `select_request(...)`
- `select_environment(...)`
- `collect_variables(...)`
- `find_template_variables(...)`
- `prompt_missing_variables(...)`
- `load_oc_request(path)`
- `build_request_from_oc(...)`
- `resolve_oauth2_token(...)`
- `load_cached_token(...)`
- `save_cached_token(...)`
- `run_fzf(...)`

The adapter should translate the OpenCollection request into an internal namespace compatible with the existing `build_curl_args` path or an equivalent curl-argument builder. Existing direct command behavior must remain covered by `tests/http-test.sh`.

---

## 12. Test Plan

Add a dedicated test file:

```text
tests/http-oc-test.sh
```

The test should use fake `HOME`, fake `~/.config/.httprc`, temporary collections, and stubbed `curl`/OAuth scripts where needed. No network calls.

Core test cases:

1. Reads `~/.config/.httprc` from fake `HOME`.
2. Discovers a collection via `opencollection.yaml`.
3. Uses `info.name` as collection name; falls back to directory name when missing.
4. Locates request by YAML basename.
5. Applies selected environment variables.
6. Applies CLI `-v`, including comma-separated values, with CLI taking precedence.
7. Fails in `--no-interactive` when a template variable is missing.
8. Builds method, URL, headers, query params, and raw JSON body from request YAML.
9. Ignores disabled headers and params.
10. Appends CLI `-H` and `-q` after request-derived values.
11. Adds default Content-Type for raw body when absent.
12. Does not override explicit Content-Type.
13. Errors on unsupported auth/body types.
14. OAuth2 client credentials obtains token through stubbed subprocess/curl path.
15. Token cache is reused when valid.
16. Expired token cache is ignored.
17. `-n/--dry-run` prints curl command and does not execute curl.
18. `--no-interactive` errors when collection/request/environment choice is missing or ambiguous.

Existing `tests/http-test.sh` remains responsible for the current direct CLI.

Validation commands:

```sh
python3 -m py_compile general/bin/http
bash tests/http-test.sh
bash tests/http-oc-test.sh
```

---

## 13. Success Criteria

The feature is successful when:

- `http oc` exists and does not regress existing `http get/post/...` usage.
- `~/.config/.httprc` YAML roots are read and scanned.
- Collections are discovered by OpenCollection manifest files.
- Requests are discovered by YAML basename.
- Environments and variables resolve with the documented precedence.
- Interactive mode reduces the need to inspect collection files manually.
- `--no-interactive` provides deterministic failures for scripts/CI.
- OAuth2 client credentials and authorization code are supported with token caching.
- `tests/http-test.sh` and `tests/http-oc-test.sh` pass.
