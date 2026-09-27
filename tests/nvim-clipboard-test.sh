#!/usr/bin/env bash
# Run from the repository root in a Wayland session.
set -euo pipefail

for tool in nvim wl-copy wl-paste; do
  command -v "$tool" >/dev/null || { echo "SKIP: $tool unavailable"; exit 0; }
done
original=$(wl-paste --no-newline --type text/plain 2>/dev/null) || {
  echo 'SKIP: no text clipboard available to restore'
  exit 0
}
trap 'printf %s "$original" | wl-copy' EXIT

expected="visual-yank-clipboard-$$"
nvim -u NONE --headless \
  -c 'luafile nvim/.config/nvim/lua/config/options.lua' \
  -c "lua vim.api.nvim_buf_set_lines(0, 0, -1, false, { '$expected' }); vim.cmd('normal! ggVy')" \
  -c 'qa!'
actual=$(wl-paste --no-newline --type text/plain)
if [[ $actual != "$expected" ]]; then
  echo 'FAIL: visual yank did not reach the system clipboard' >&2
  exit 1
fi
echo 'PASS: visual yank reaches the system clipboard'
