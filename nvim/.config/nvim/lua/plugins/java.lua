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
}
