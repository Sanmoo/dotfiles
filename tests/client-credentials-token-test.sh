#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/client-credentials-token"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/bin"
mkdir -p "$STUB_DIR"

cat >"$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CURL_ARGS_FILE"
printf '{"access_token":"abc123","token_type":"Bearer"}\n'
STUB
chmod +x "$STUB_DIR/curl"

CURL_ARGS_FILE="$TMPDIR/curl.args"
export CURL_ARGS_FILE
PATH="$STUB_DIR:$PATH" "$SCRIPT" my-client my-secret https://auth.example/token >"$TMPDIR/stdout"

if [ "$(cat "$TMPDIR/stdout")" != "abc123" ]; then
	echo "Expected stdout to contain only access_token" >&2
	exit 1
fi

if grep -q -- '--user' "$CURL_ARGS_FILE"; then
	echo "Expected curl not to use HTTP Basic auth" >&2
	cat "$CURL_ARGS_FILE" >&2
	exit 1
fi

if ! grep -q -- '-d grant_type=client_credentials' "$CURL_ARGS_FILE"; then
	echo "Expected curl to request client_credentials grant in form body" >&2
	cat "$CURL_ARGS_FILE" >&2
	exit 1
fi

if ! grep -q -- '-d client_id=my-client' "$CURL_ARGS_FILE"; then
	echo "Expected curl to send client_id in form body" >&2
	cat "$CURL_ARGS_FILE" >&2
	exit 1
fi

if ! grep -q -- '-d client_secret=my-secret' "$CURL_ARGS_FILE"; then
	echo "Expected curl to send client_secret in form body" >&2
	cat "$CURL_ARGS_FILE" >&2
	exit 1
fi

if ! grep -q -- 'https://auth.example/token' "$CURL_ARGS_FILE"; then
	echo "Expected curl to call token URL" >&2
	cat "$CURL_ARGS_FILE" >&2
	exit 1
fi
