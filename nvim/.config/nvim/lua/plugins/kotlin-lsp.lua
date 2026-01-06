return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local configs = require("lspconfig.configs")
      local util = require("lspconfig.util")

      configs.kotlin_lsp = {
        default_config = {
          cmd = { "kotlin-lsp", "--stdio" },
          filetypes = { "kotlin" },
          root_dir = util.root_pattern(
            "settings.gradle",
            "settings.gradle.kts",
            "pom.xml",
            "build.gradle",
            "build.gradle.kts",
            "workspace.json"
          ),
        },
      }

      opts.servers.kotlin_lsp = {}
    end,
  },
}
