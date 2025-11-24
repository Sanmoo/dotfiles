return {
  -- Fixes anoying ST1000 error from LSP. Let golangci-lint handle all linting instead
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
