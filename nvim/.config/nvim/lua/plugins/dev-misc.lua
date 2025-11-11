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
    -- {
    --   "kndndrj/nvim-dbee",
    --   dependencies = {
    --     "MunifTanjim/nui.nvim",
    --   },
    --   build = function()
    --     -- Install tries to automatically detect the install method.
    --     -- if it fails, try calling it with one of these parameters:
    --     --    "curl", "wget", "bitsadmin", "go"
    --     require("dbee").install()
    --   end,
    --   config = function()
    --     require("dbee").setup(--[[optional config]])
    --   end,
    --   opts = { enabled = false },
    -- },
  },
}
