return {
  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = {
      "olimorris/neotest-phpunit",
    },
    opts = {
      adapters = {
        ["neotest-phpunit"] = {
          env = {
            XDEBUG_CONFIG = "start_with_request=yes idekey=neotest",
            XDEBUG_MODE = "debug",
          },
          dap = {
            log = true,
            type = "php",
            request = "launch",
            name = "Listen for XDebug",
            port = 9003,
            stopOnEntry = false,
            xdebugSettings = {
              max_children = -1,
              max_data = -1,
              max_depth = -1,
            },
            -- breakpoints = {
            --   exception = {
            --     Notice = false,
            --     Warning = false,
            --     Error = false,
            --     Exception = false,
            --     ["*"] = true,
            --   },
            -- },
          },
        },
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
  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      local dap = require("dap")
      dap.adapters.php = {
        type = "executable",
        command = "php-debug-adapter",
        args = {},
      }
    end,
  },
}
