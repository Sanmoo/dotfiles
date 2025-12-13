return {
  {
    "vinnymeller/swagger-preview.nvim",
    cmd = { "SwaggerPreview", "SwaggerPreviewStop", "SwaggerPreviewToggle" },
    build = "npm i",
    config = true,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- kotlin_language_server = {
        --   enabled = true,
        -- },
        -- Enable Kotlin Language Server
        --
        -- Not working for me
        kotlin_lsp = {
          enabled = false,
        },

        -- Enable TypeSpec Server
        tsp_server = {},
        emmet_language_server = {},
      },
    },
    { "weilbith/neotest-gradle" },
    {
      "nvim-neotest/neotest",
      opts = { adapters = { "neotest-gradle" } },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "emmet-language-server",
      },
    },
  },
  {
    "olrtg/nvim-emmet",
    config = function()
      vim.keymap.set({ "n", "v" }, "<leader>xe", require("nvim-emmet").wrap_with_abbreviation)
    end,
  },
}
