#!/usr/bin/env bash
# Tests for general/bin/http. Stubs curl and asserts on the recorded argv.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/http"

assert_contains() {
 local haystack="$1" needle="$2" message="$3"
 if ! grep -Fq -- "$needle" "$haystack"; then
  echo "FAIL: $message" >&2
  echo "  expected to find: $needle" >&2
  echo "  in:" >&2
  sed 's/^/    /' "$haystack" >&2
  exit 1
 fi
}

assert_not_contains() {
 local haystack="$1" needle="$2" message="$3"
 if grep -Fq -- "$needle" "$haystack"; then
  echo "FAIL: $message" >&2
  echo "  expected NOT to find: $needle" >&2
  echo "  in:" >&2
  sed 's/^/    /' "$haystack" >&2
  exit 1
 fi
}

run_http_expect_fail() {
 # run_http_expect_fail <args...>
 # Like run_http but expects non-zero exit. Sets HTTP_EXIT to the exit code.
 local tmpdir
 tmpdir="$(mktemp -d)"
 HTTP_TMPDIR="$tmpdir"
 HTTP_EXIT=0
 "$SCRIPT" "$@" >"$tmpdir/stdout" 2>"$tmpdir/err" || HTTP_EXIT=$?
 HTTP_STDERR="$(cat "$tmpdir/err")"
}


run_http() {
 # run_http <args...>
 # Sets HTTP_CURL_ARGS -> printed curl command (stdout)
 # Sets HTTP_STUB_LOG -> stub curl's recorded argv (for live-execution tests)
 local tmpdir
 tmpdir="$(mktemp -d)"
 mkdir -p "$tmpdir/bin"
 cat >"$tmpdir/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CURL_ARGS_FILE"
STUB
 chmod +x "$tmpdir/bin/curl"

 HTTP_CURL_ARGS="$tmpdir/curl.args"
 export CURL_ARGS_FILE="$HTTP_CURL_ARGS"
 PATH="$tmpdir/bin:$PATH" "$SCRIPT" "$@" >"$tmpdir/stdout" 2>"$tmpdir/stderr"
 HTTP_CURL_ARGS="$tmpdir/stdout"  # use printed output, not stub log
 HTTP_STUB_LOG="$tmpdir/curl.args"
 HTTP_STDOUT="$(cat "$tmpdir/stdout")"
 HTTP_STDERR="$(cat "$tmpdir/stderr")"
 HTTP_TMPDIR="$tmpdir"
}

# ---------- Test 1: simplest post call ----------
echo "test 1: simplest post"
unset HTTP_BASE_URL BASE_URL
run_http post -B https://api.example.com foo
assert_contains "$HTTP_CURL_ARGS" "-X POST" "post should emit -X POST"
assert_contains "$HTTP_CURL_ARGS" "https://api.example.com/foo" "url should be base + path"
assert_not_contains "$HTTP_CURL_ARGS" "-X GET" "post should not include -X GET"

# ---------- Test 2: get emits no -X ----------
echo "test 2: get emits no -X"
run_http get -B https://api.example.com items/42
assert_not_contains "$HTTP_CURL_ARGS" "-X " "get should not set -X"
assert_contains "$HTTP_CURL_ARGS" "https://api.example.com/items/42" "url with id"

# ---------- Test 3: delete emits -X DELETE ----------
echo "test 3: delete emits -X DELETE"
run_http delete -B https://api.example.com items/42
assert_contains "$HTTP_CURL_ARGS" "-X DELETE" "delete should emit -X DELETE"
assert_contains "$HTTP_CURL_ARGS" "https://api.example.com/items/42" "url with id"

# ---------- Test 4: path with leading slash does not produce double slash ----------
echo "test 4: dedup of leading slash in path"
run_http get -B https://api.example.com/ /items/42
assert_contains "$HTTP_CURL_ARGS" "https://api.example.com/items/42" "no double slash"
assert_not_contains "$HTTP_CURL_ARGS" "https://api.example.com//items" "no double slash (negative)"

# ---------- Test 5: -i, -k, -L pass through ----------
echo "test 5: -i, -k, -L pass through"
run_http post -B https://api.example.com -i -k -L foo
grep -Fq -- ' -i ' "$HTTP_CURL_ARGS" || { echo "FAIL: -i missing" >&2; exit 1; }
grep -Fq -- ' -k ' "$HTTP_CURL_ARGS" || { echo "FAIL: -k missing" >&2; exit 1; }
grep -Fq -- ' -L ' "$HTTP_CURL_ARGS" || { echo "FAIL: -L missing" >&2; exit 1; }

# ---------- Test 6: -B flag wins over HTTP_BASE_URL and BASE_URL ----------
echo "test 6: -B flag precedence"
HTTP_BASE_URL="https://from-env-http.example.com" BASE_URL="https://from-base.example.com" \
  run_http get -B https://from-flag.example.com foo
assert_contains "$HTTP_CURL_ARGS" "https://from-flag.example.com/foo" "flag wins"

# ---------- Test 7: HTTP_BASE_URL wins over BASE_URL ----------
echo "test 7: HTTP_BASE_URL wins over BASE_URL"
HTTP_BASE_URL="https://from-env-http.example.com" BASE_URL="https://from-base.example.com" \
  run_http get foo
assert_contains "$HTTP_CURL_ARGS" "https://from-env-http.example.com/foo" "HTTP_BASE_URL wins"

# ---------- Test 8: BASE_URL is the fallback ----------
echo "test 8: BASE_URL fallback"
BASE_URL="https://from-base.example.com" run_http get foo
assert_contains "$HTTP_CURL_ARGS" "https://from-base.example.com/foo" "BASE_URL fallback"

# ---------- Test 9: no base URL is an error ----------
echo "test 9: no base URL is an error"
unset HTTP_BASE_URL BASE_URL
run_http_expect_fail get foo
[ "$HTTP_EXIT" -ne 0 ] || { echo "FAIL: expected non-zero exit" >&2; exit 1; }
assert_contains "$HTTP_TMPDIR/err" "no base URL provided" "error message"

# ---------- Test 10: -H stacks and preserves order ----------
echo "test 10: -H stacks"
run_http get -B https://api.example.com \
  -H "X-Foo: bar" -H "Accept: application/json" foo
grep -Fq -- "X-Foo: bar" "$HTTP_CURL_ARGS" || { echo "FAIL: -H X-Foo" >&2; exit 1; }
grep -Fq -- "Accept: application/json" "$HTTP_CURL_ARGS" || { echo "FAIL: -H Accept" >&2; exit 1; }

# ---------- Test 11: -t expands to Authorization header ----------
echo "test 11: -t bearer"
run_http get -B https://api.example.com -t "abc123" foo
grep -Fq -- "Authorization: Bearer abc123" "$HTTP_CURL_ARGS" || { echo "FAIL: bearer" >&2; exit 1; }

# ---------- Test 12: -t with empty value is an error ----------
echo "test 12: empty -t is an error"
run_http_expect_fail get -B https://api.example.com -t "" foo
[ "$HTTP_EXIT" -ne 0 ] || { echo "FAIL: expected non-zero" >&2; exit 1; }
assert_contains "$HTTP_TMPDIR/err" "--token is empty" "empty token error"

# ---------- Test 13: -t and explicit Authorization both pass through ----------
echo "test 13: -t and explicit Authorization"
run_http get -B https://api.example.com -t "abc" -H "Authorization: Bearer xyz" foo
grep -Fq -- "Authorization: Bearer abc" "$HTTP_CURL_ARGS" || { echo "FAIL: -t header missing" >&2; exit 1; }
grep -Fq -- "Authorization: Bearer xyz" "$HTTP_CURL_ARGS" || { echo "FAIL: explicit -H missing" >&2; exit 1; }

echo "OK"
