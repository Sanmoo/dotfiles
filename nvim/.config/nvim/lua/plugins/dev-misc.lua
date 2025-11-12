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
        kotlin_language_server = {
          -- enabled = false
        },
        -- Enable Kotlin Language Server
        --
        -- Not working for me
        kotlin_lsp = {
          enabled = false,
        },

        -- Enable TypeSpec Server
        tsp_server = {},
      },
    },
    { "weilbith/neotest-gradle" },
    {
      "nvim-neotest/neotest",
      opts = { adapters = { "neotest-gradle" } },
    },

    -- SQL stuff
    -- {
    --   "tpope/vim-dadbod",
    --   opts = {
    --     enabled = true,
    --   },
    -- },
    -- {
    --   "kristijanhusak/vim-dadbod-completion",
    --   opts = {
    --     enabled = true,
    --   },
    -- },
    -- {
    --   "kristijanhusak/vim-dadbod-ui",
    --   opts = {
    --     enabled = true,
    --   },
    -- },
  },
}
