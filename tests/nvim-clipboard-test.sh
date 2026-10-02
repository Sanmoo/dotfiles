#!/usr/bin/env bash
# Run from the repository root in a Wayland session.
#
# Covers both clipboard paths of nvim/.config/nvim/lua/config/options.lua:
#   - direct session: a visual yank reaches the system clipboard
#   - proxied session (herdr pane / SSH): a visual yank is written to the terminal
#     as an OSC 52 copy, which herdr forwards to the client the human is using
set -euo pipefail

optfile="nvim/.config/nvim/lua/config/options.lua"

for tool in nvim wl-copy wl-paste python3 script; do
  command -v "$tool" >/dev/null || { echo "SKIP: $tool unavailable"; exit 0; }
done

original=$(wl-paste --no-newline --type text/plain 2>/dev/null) || {
  echo 'SKIP: no text clipboard available to restore'
  exit 0
}
trap 'printf %s "$original" | wl-copy' EXIT

expected="visual-yank-clipboard-$$"

# Direct session: the yank must reach the system clipboard.
env -u HERDR_PANE_ID -u SSH_CONNECTION -u SSH_TTY \
  nvim -u NONE --headless \
  -c "luafile $optfile" \
  -c "lua vim.api.nvim_buf_set_lines(0, 0, -1, false, { '$expected' }); vim.cmd('normal! ggVy')" \
  -c 'qa!'
actual=$(wl-paste --no-newline --type text/plain)
if [[ $actual != "$expected" ]]; then
  echo 'FAIL: visual yank did not reach the system clipboard' >&2
  exit 1
fi
echo 'PASS: visual yank reaches the system clipboard'

# Proxied session: the yank must be written to the terminal as an OSC 52 copy.
# A pty is required because nvim_ui_send produces no output without an attached UI.
runner=$(mktemp)
trap 'rm -f "$runner"; printf %s "$original" | wl-copy' EXIT
cat >"$runner" <<EOF
nvim -u NONE \\
  -c "luafile $optfile" \\
  -c "lua vim.api.nvim_buf_set_lines(0, 0, -1, false, { '$expected' }); vim.cmd('normal! ggVy')" \\
  -c 'qa!'
EOF
payload=$(
  env -u SSH_CONNECTION -u SSH_TTY HERDR_PANE_ID=test \
    script -qec "sh $runner" /dev/null 2>/dev/null | python3 -c '
import base64, re, sys
data = sys.stdin.buffer.read()
match = re.search(rb"\x1b\]52;c;([A-Za-z0-9+/=]*)", data)
sys.stdout.write(base64.b64decode(match.group(1)).decode() if match else "")
'
)
if [[ $payload != *"$expected"* ]]; then
  echo "FAIL: proxied visual yank did not emit an OSC 52 copy (got: ${payload@Q})" >&2
  exit 1
fi
echo 'PASS: proxied visual yank emits an OSC 52 copy'
