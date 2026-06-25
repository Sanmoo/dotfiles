return {
  {
    -- Override the LazyVim leap extra config which uses deprecated
    -- add_default_mappings() that references removed <Plug> keys
    -- (<Plug>(leap-forward-to) / <Plug>(leap-backward-to)).
    -- See :help leap-mappings for the current API.
    url = "https://codeberg.org/andyg/leap.nvim.git",
    enabled = true,
    opts = {
      labeled_modes = "nx", -- show labels in normal + visual, not operator-pending
    },
    config = function(_, opts)
      local leap = require("leap")
      for k, v in pairs(opts) do
        leap.opts[k] = v
      end
      -- Default mappings (see :help leap-mappings)
      -- s: bidirectional leap in current window
      vim.keymap.set({ "n", "x", "o" }, "s", "<Plug>(leap)", { silent = true, desc = "Leap" })
      -- S: leap to other windows
      vim.keymap.set({ "n", "x", "o" }, "S", "<Plug>(leap-from-window)", { silent = true, desc = "Leap from Window" })
      -- gs: leap to other windows
      vim.keymap.set({ "n", "x", "o" }, "gs", "<Plug>(leap-from-window)", { silent = true, desc = "Leap from Window" })
    end,
    keys = {
      { "s", mode = { "n", "x", "o" }, desc = "Leap" },
      { "S", mode = { "n", "x", "o" }, desc = "Leap from Window" },
      { "gs", mode = { "n", "x", "o" }, desc = "Leap from Window" },
    },
  },
}
