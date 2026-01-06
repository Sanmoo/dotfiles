return {
  {
    "vinnymeller/swagger-preview.nvim",
    cmd = { "SwaggerPreview", "SwaggerPreviewStop", "SwaggerPreviewToggle" },
    build = "npm i",
    config = true,
  },
  { "weilbith/neotest-gradle" },
  {
    "nvim-neotest/neotest",
    opts = { adapters = { "neotest-gradle" } },
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
  {
    -- solves highlight issue in insert parts
    "pmouraguedes/sql-ghosty.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {},
  },
}
