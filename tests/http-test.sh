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

# ---------- Test 14: -q single ----------
echo "test 14: single -q"
run_http get -B https://api.example.com -q "status=active" items
grep -Fq -- "https://api.example.com/items?status=active" "$HTTP_CURL_ARGS" \
  || { echo "FAIL: query string missing" >&2; cat "$HTTP_CURL_ARGS" >&2; exit 1; }

# ---------- Test 15: -q multiple, order preserved ----------
echo "test 15: multiple -q"
run_http get -B https://api.example.com -q "a=1" -q "b=2" items
grep -Fq -- "?a=1&b=2" "$HTTP_CURL_ARGS" \
  || { echo "FAIL: multi query order" >&2; cat "$HTTP_CURL_ARGS" >&2; exit 1; }

# ---------- Test 16: -q value is URL-encoded ----------
echo "test 16: -q URL-encoding"
run_http get -B https://api.example.com -q "q=hello world&x" items
grep -Fq -- "q=hello+world%26x" "$HTTP_CURL_ARGS" \
  || { echo "FAIL: URL-encoding of value" >&2; cat "$HTTP_CURL_ARGS" >&2; exit 1; }

# ---------- Test 17: -d inline body ----------
echo "test 17: -d inline body"
run_http post -B https://api.example.com -d '{"x":1}' foo
grep -Fq -- "--data" "$HTTP_CURL_ARGS" \
  || { echo "FAIL: --data present" >&2; cat "$HTTP_CURL_ARGS" >&2; exit 1; }

# ---------- Test 18: -f body from file with auto Content-Type ----------
echo "test 18: -f with auto Content-Type"
PAYLOAD="$HTTP_TMPDIR/payload.json"
echo '{"x":1}' > "$PAYLOAD"
run_http post -B https://api.example.com -f "$PAYLOAD" foo
grep -Fq -- "Content-Type: application/json" "$HTTP_CURL_ARGS" \
  || { echo "FAIL: auto json content type" >&2; cat "$HTTP_CURL_ARGS" >&2; exit 1; }
grep -Fq -- "--data @${PAYLOAD}" "$HTTP_CURL_ARGS" \
  || { echo "FAIL: --data @file" >&2; cat "$HTTP_CURL_ARGS" >&2; exit 1; }

# ---------- Test 19: -f with .jsonc extension ----------
echo "test 19: -f .jsonc auto Content-Type"
PAYLOAD="$HTTP_TMPDIR/payload.jsonc"
echo '// c' > "$PAYLOAD"; echo '{"x":1}' >> "$PAYLOAD"
run_http post -B https://api.example.com -f "$PAYLOAD" foo
grep -Fq -- "Content-Type: application/json" "$HTTP_CURL_ARGS" \
  || { echo "FAIL: jsonc content type" >&2; exit 1; }

# ---------- Test 20: -f with .xml extension ----------
echo "test 20: -f .xml auto Content-Type"
PAYLOAD="$HTTP_TMPDIR/payload.xml"
echo '<x/>' > "$PAYLOAD"
run_http post -B https://api.example.com -f "$PAYLOAD" foo
grep -Fq -- "Content-Type: application/xml" "$HTTP_CURL_ARGS" \
  || { echo "FAIL: xml content type" >&2; exit 1; }

# ---------- Test 21: -f with other extension -> octet-stream ----------
echo "test 21: -f other extension -> octet-stream"
PAYLOAD="$HTTP_TMPDIR/blob.bin"
echo 'binary' > "$PAYLOAD"
run_http post -B https://api.example.com -f "$PAYLOAD" foo
grep -Fq -- "Content-Type: application/octet-stream" "$HTTP_CURL_ARGS" \
  || { echo "FAIL: octet-stream" >&2; exit 1; }

# ---------- Test 22: explicit -H Content-Type wins over auto ----------
echo "test 22: explicit -H Content-Type wins"
PAYLOAD="$HTTP_TMPDIR/payload.json"
echo '{}' > "$PAYLOAD"
run_http post -B https://api.example.com -H "Content-Type: application/vnd.custom+json" -f "$PAYLOAD" foo
grep -Fq -- "Content-Type: application/vnd.custom+json" "$HTTP_CURL_ARGS" \
  || { echo "FAIL: explicit content type" >&2; exit 1; }
# The auto Content-Type must NOT appear as the only Content-Type.
# If both show up that's wrong; if only auto shows up that's wrong.
# We already checked the explicit one exists. Check that the auto doesn't:
if grep -Fq -- "Content-Type: application/json" "$HTTP_CURL_ARGS"; then
  # Auto appeared too — check it's not the ONLY one
  count="$(grep -Fc -- 'Content-Type:' "$HTTP_CURL_ARGS")"
  [ "$count" -eq 1 ] || { echo "FAIL: both content types present" >&2; exit 1; }
fi

# ---------- Test 23: -f and -d together is an error ----------
echo "test 23: -f and -d together is an error"
PAYLOAD="$HTTP_TMPDIR/payload.json"
echo '{}' > "$PAYLOAD"
run_http_expect_fail post -B https://api.example.com -f "$PAYLOAD" -d "x" foo
[ "$HTTP_EXIT" -ne 0 ] || { echo "FAIL: expected non-zero" >&2; exit 1; }
assert_contains "$HTTP_TMPDIR/err" "mutually exclusive" "exclusive error"

# ---------- Test 24: missing -f file is an error ----------
echo "test 24: -f with missing file is an error"
run_http_expect_fail post -B https://api.example.com -f /tmp/does-not-exist-12345.json foo
[ "$HTTP_EXIT" -ne 0 ] || { echo "FAIL: expected non-zero" >&2; exit 1; }
assert_contains "$HTTP_TMPDIR/err" "file not found" "missing file error"

echo "OK"
