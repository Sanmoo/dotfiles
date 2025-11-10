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
          enabled = false
        },
        -- Enable Kotlin Language Server
        -- Not working for me
        -- kotlin_lsp = {},
        -- Not working for me either
        -- kotlin_language_server = {},

        -- Enable TypeSpec Server
        tsp_server = {},
      }
    }
  }
}
