return {
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "tsp-server" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        typespec = {}, -- The name lspconfig uses for the TypeSpec server might be 'typespec' or 'typespec-ls'.
      },
    },
  },
}
