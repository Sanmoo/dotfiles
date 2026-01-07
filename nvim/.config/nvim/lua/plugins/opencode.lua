return {
  {
    "NickvanDyke/opencode.nvim",
    dependencies = {
      -- Recommended for `ask()` and `select()`.
      -- Required for `snacks` provider.
      ---@module 'snacks' <- Loads `snacks.nvim` types for configuration intellisense.
      -- { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
    },
    config = function()
      ---@type opencode.Opts
      vim.g.opencode_opts = {
        -- Your configuration, if any — see `lua/opencode/config.lua`, or "goto definition".
      }

      -- Required for `opts.events.reload`.
      vim.o.autoread = true
    end,
    keys = {
      {
        "<leader>oa",
        function()
          require("opencode").ask("@this: ", { submit = true })
        end,
        mode = { "n", "x" },
        desc = "Opencode: Ask",
      },
      {
        "<leader>oo",
        function()
          require("opencode").toggle()
        end,
        mode = { "n", "x" },
        desc = "Toggle Opencode",
      },
      {
        "<leader>os",
        function()
          require("opencode").select()
        end,
        mode = { "n", "t" },
        desc = "Execute opencode action",
      },
      {
        "<leader>or",
        function()
          return require("opencode").operator("@this ")
        end,
        mode = { "n", "x" },
        expr = true,
        desc = "Add range to opencode",
      },
      {
        "<leader>ol",
        function()
          return require("opencode").operator("@this ") .. "_"
        end,
        mode = { "n" },
        expr = true,
        desc = "Add line to opencode",
      },
      {
        "<leader>ou",
        function()
          return require("opencode").command("session.half.page.up")
        end,
        mode = { "n" },
        desc = "opencode half page up",
      },
      {
        "<leader>od",
        function()
          return require("opencode").command("session.half.page.down")
        end,
        mode = { "n" },
        desc = "opencode half page down",
      },
      {
        "<leader>o+",
        function()
          return require("opencode").command("session.half.page.down")
        end,
        mode = { "n" },
        desc = "opencode half page down",
      },
    },
  },
  {
    "zhisme/copy_with_context.nvim",
    config = function()
      require("copy_with_context").setup({
        -- Customize mappings
        mappings = {
          relative = "<leader>cy",
          absolute = "<leader>cY",
          remote = "<leader>cr",
        },
        formats = {
          default = "# {filepath}:{line}", -- Used by relative and absolute mappings
          remote = "# {remote_url}",
        },
        -- whether to trim lines or not
        trim_lines = false,
      })
    end,
  },
}
