return {
  {
    "akinsho/bufferline.nvim",
    -- Disabling since I hate tabs
    enabled = false,
  },
  {
    "christoomey/vim-tmux-navigator",
    enabled = false,
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
      "TmuxNavigatorProcessList",
    },
    keys = {
      { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>" },
      { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>" },
      { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>" },
      { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>" },
      { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>" },
    },
  },
  {
    "nvim-telescope/telescope.nvim",
    keys = {
      {
        "<leader>sf",
        "<cmd>Telescope find_files hidden=true no_ignore=true<cr>",
        desc = "Find files, including hidden and ignored",
      },
      {
        "<leader>sz",
        function()
          require("telescope.builtin").live_grep({
            additional_args = { "--no-ignore-vcs", "--hidden" },
          })
        end,
        desc = "Grep files, including hidden and ignored",
      },
    },
  },
  {
    "s1n7ax/nvim-window-picker",
    name = "window-picker",
    event = "VeryLazy",
    version = "2.*",
    config = function()
      require("window-picker").setup()
    end,
  },
  -- Other UI plugins...
}
