#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/herdr/.config/herdr/config.toml"

if grep -Eq '^open_notification_target = "prefix\+o"' "$CONFIG"; then
	printf 'Expected open_notification_target to be disabled for prefix+o\n' >&2
	exit 1
fi

if ! grep -Eq '^delivery = "herdr"' "$CONFIG"; then
	printf 'Expected in-app Herdr delivery so toasts stay visible\n' >&2
	exit 1
fi

# True when the config contains a `[[keys.command]]` block whose text matches
# the given extended regex. Every block is evaluated at any section boundary,
# including when another `[[keys.command]]` header terminates it. The pattern
# is passed through the environment rather than `awk -v`, which would consume
# the backslash in `prefix\+o` and stop it matching a literal `+`.
block_contains() { # <pattern> <config>
	PATTERN=$1 awk '
		function flush() {
			if (in_command && block ~ ENVIRON["PATTERN"]) found = 1
			in_command = 0
		}
		/^\[\[?[^]]/ { flush(); if ($0 == "[[keys.command]]") { in_command = 1; block = $0 ORS } next }
		in_command { block = block $0 ORS }
		END { flush(); exit found ? 0 : 1 }
	' "$2"
}

if ! block_contains 'key = "prefix\+o"' "$CONFIG"; then
	printf 'Expected custom keys.command binding for prefix+o\n' >&2
	exit 1
fi

if ! block_contains 'focus-next-actionable-agent\.sh' "$CONFIG"; then
	printf 'Expected prefix+o command to run focus-next-actionable-agent.sh\n' >&2
	exit 1
fi

printf 'herdr notification target tests passed\n'
