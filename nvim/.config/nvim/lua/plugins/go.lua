return {
  -- Fixes anoying ST1000 error from LSP. Let golangci-lint handle all linting instead
  {
    "fredrikaverpil/neotest-golang",
    dependencies = {
      {
        "nvim-treesitter/nvim-treesitter", -- Optional, but recommended
        branch = "main", -- NOTE; not the master branch!
        build = function()
          vim.cmd(":TSUpdate go")
        end,
      },
      {
        "fredrikaverpil/neotest-golang",
        version = "*", -- Optional, but recommended; track releases
        build = function()
          vim.system({ "go", "install", "gotest.tools/gotestsum@latest" }):wait() -- Optional, but recommended
        end,
      },
    },
  },
  -- {
  --   "nvim-neotest/neotest",
  --   opts = {
  --     adapters = {
  --       ["neotest-golang"] = {
  --         runner = "gotestsum", -- In my omarchy I could not make it work with default
  --       },
  --     },
  --   },
  -- },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gopls = {
          settings = {
            gopls = {
              analyses = {
                ST1000 = false,
              },
            },
          },
        },
      },
    },
  },
}
