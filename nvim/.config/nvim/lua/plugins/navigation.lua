return {
  {
    "akinsho/bufferline.nvim",
    enabled = false, -- Set this to false to disable the plugin
  },
  {
    "christoomey/vim-tmux-navigator",
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
  -- Other UI plugins...
}
