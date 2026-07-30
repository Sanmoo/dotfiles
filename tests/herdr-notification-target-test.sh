#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/herdr/.config/herdr/config.toml"

if ! grep -Eq '^open_notification_target = "prefix\+o"' "$CONFIG"; then
	printf 'Expected prefix+o to use native open_notification_target\n' >&2
	exit 1
fi

if ! grep -Eq '^delivery = "herdr"' "$CONFIG"; then
	printf 'Expected in-app Herdr delivery so notification target remains available\n' >&2
	exit 1
fi

if awk '
	/^\[\[keys\.command\]\]$/ { in_command = 1; block = $0 ORS; next }
	in_command && /^\[\[/ { if (block ~ /key = "prefix\+o"/) found = 1; in_command = 0 }
	in_command { block = block $0 ORS }
	END { if (in_command && block ~ /key = "prefix\+o"/) found = 1; exit found ? 0 : 1 }
' "$CONFIG"; then
	printf 'Expected no custom keys.command binding for prefix+o\n' >&2
	exit 1
fi

printf 'herdr notification target tests passed\n'
