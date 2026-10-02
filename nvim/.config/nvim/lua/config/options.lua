-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.relativenumber = false
vim.opt.spelllang = { "en", "pt" }
vim.opt.clipboard:append("unnamedplus")

-- Inside a herdr pane or an SSH session the desktop clipboard is out of reach:
-- herdr runs on the machine Neovim runs on, while the human may be attached from
-- another machine. herdr forwards OSC 52 clipboard writes from its panes to the
-- terminal the human is looking at, but it does not answer OSC 52 reads. So route
-- copies through OSC 52 and keep pastes on the local system tools.
if vim.env.HERDR_PANE_ID or vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
  local osc52 = require("vim.ui.clipboard.osc52")

  local function system_paste(primary)
    if vim.fn.has("mac") == 1 then
      return "pbpaste"
    end
    if vim.env.WAYLAND_DISPLAY and vim.fn.executable("wl-paste") == 1 then
      return primary and "wl-paste --no-newline --primary" or "wl-paste --no-newline"
    end
    if vim.fn.executable("xclip") == 1 then
      return primary and "xclip -selection primary -o" or "xclip -selection clipboard -o"
    end
    return function()
      return {}
    end
  end

  vim.g.clipboard = {
    name = "OSC 52 copy",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = system_paste(false), ["*"] = system_paste(true) },
    cache_enabled = 1,
  }
end
