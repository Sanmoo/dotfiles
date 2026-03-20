return {
  {
    "mfussenegger/nvim-jdtls",
    opts = {
      settings = {
        java = {
          import = {
            gradle = {
              java = {
                home = vim.env.JAVA_HOME,
              },
            },
          },
          configuration = {
            runtimes = {
              {
                name = "JavaSE-25",
                path = vim.env.JAVA_HOME,
                default = true,
              },
            },
          },
        },
      },
    },
  },

  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = { "checkstyle" },
    },
  },

  {
    "mfussenegger/nvim-lint",
    optional = true,
    dependencies = "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.java = opts.linters_by_ft.java or {}

      local cwd = vim.fn.getcwd()
      local config_paths = {
        cwd .. "/config/checkstyle/checkstyle.xml",
        cwd .. "/checkstyle.xml",
      }

      local checkstyle_config = nil
      for _, path in ipairs(config_paths) do
        if vim.fn.filereadable(path) == 1 then
          checkstyle_config = path
          break
        end
      end

      if checkstyle_config then
        table.insert(opts.linters_by_ft.java, "checkstyle")

        local config_dir = vim.fn.fnamemodify(checkstyle_config, ":h")
        local suppressions = config_dir .. "/suppressions.xml"

        require("lint.linters.checkstyle").config_file = checkstyle_config

        if vim.fn.filereadable(suppressions) == 1 then
          -- Read checkstyle.xml to find the property name used in SuppressionFilter
          -- e.g. ${suppressionFile} or ${org.checkstyle.suppressions.file}
          local prop_name = "suppressionFile"
          local xml = io.open(checkstyle_config, "r")
          if xml then
            local content = xml:read("*a")
            xml:close()
            local found = content:match('%${([^}]+)}.-[Ss]uppression')
              or content:match('[Ss]uppression.-${([^}]+)}')
            if found then
              prop_name = found
            end
          end

          local props_file = vim.fn.tempname() .. ".properties"
          local f = io.open(props_file, "w")
          if f then
            f:write(prop_name .. "=" .. suppressions .. "\n")
            f:close()
            opts.linters = opts.linters or {}
            opts.linters.checkstyle = {
              prepend_args = { "-p", props_file },
            }
          end
        end
      end
    end,
  },
}
