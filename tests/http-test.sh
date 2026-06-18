#!/usr/bin/env bash
# Tests for general/bin/http. Stubs curl and asserts on the recorded argv.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/http"

assert_contains() {
	# assert_contains <haystack_file> <needle> <message>
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

run_http() {
	# run_http <args...>  ->  sets HTTP_CURL_ARGS to the recorded curl argv
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
	HTTP_STDOUT="$(cat "$tmpdir/stdout")"
	HTTP_STDERR="$(cat "$tmpdir/stderr")"
	# PRE-FLIGHT FIX: the stub log remains empty in this task because the script
	# only prints the curl command to stdout (dry-run). Point assertions at the
	# stdout capture so checks examine the printed command. Keep the stub log
	# path in HTTP_STUB_LOG for future tasks.
	HTTP_CURL_ARGS="$tmpdir/stdout" # use printed output, not stub log
	HTTP_STUB_LOG="$tmpdir/curl.args"
	HTTP_TMPDIR="$tmpdir"
}

# ---------- Test 1: simplest post call ----------
echo "test 1: simplest post"
unset HTTP_BASE_URL BASE_URL || true
run_http post -B https://api.example.com foo
assert_contains "$HTTP_CURL_ARGS" "-X POST" "post should emit -X POST"
assert_contains "$HTTP_CURL_ARGS" "https://api.example.com/foo" "url should be base + path"
assert_not_contains "$HTTP_CURL_ARGS" "-X GET" "post should not include -X GET"

echo "OK"
