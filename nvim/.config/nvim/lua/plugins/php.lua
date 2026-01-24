return {
  {
    "nvim-neotest/neotest",
    lazy = true,
    dependencies = {
      "olimorris/neotest-phpunit",
    },
    opts = {
      adapters = {
        require("neotest-phpunit")({
          phpunit_cmd = "./vendor/bin/phpunit",
        }),
      },
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        php = { "php_cs_fixer" },
      },
    },
  },
}
