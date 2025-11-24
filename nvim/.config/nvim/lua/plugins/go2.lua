return {
  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = {
      "fredrikaverpil/neotest-golang",
    },
    opts = {
      adapters = {
        ["neotest-golang"] = {
          -- Specify gotestsum as the test runner
          runner = "gotestsum",
          -- Optionally, you can also pass additional arguments to go test
          go_test_args = { "-v", "-race", "-count=1" },
          -- Enable DAP integration if desired (requires nvim-dap-go)
          dap_go_enabled = true,
        },
      },
    },
  },
}
