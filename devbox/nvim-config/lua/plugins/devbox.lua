-- Devbox: always show hidden files (.env, .gitignore, etc.) in Telescope and Netrw
-- This file is copied to ~/.config/nvim/lua/plugins/ by devbox entrypoint

return {
  {
    "nvim-telescope/telescope.nvim",
    keys = {
      {
        "<leader>ff",
        function()
          require("lazyvim.util").telescope("files", { hidden = true, no_ignore = true })()
        end,
        desc = "Find files (root dir)",
      },
      {
        "<leader>fF",
        function()
          require("lazyvim.util").telescope("files", { hidden = true, no_ignore = true })()
        end,
        desc = "Find files (root dir, no gitignore)",
      },
    },
    opts = function(_, opts)
      opts.pickers = vim.tbl_deep_extend("force", opts.pickers or {}, {
        find_files = { hidden = true, no_ignore = true },
        oldfiles = { hidden = true },
      })
      return opts
    end,
    config = function()
      -- Netrw and wildmenu: show dotfiles in :Ex and :e
      vim.g.netrw_hide = 0
      vim.g.netrw_list_hide = ""
      vim.opt.wildignorecase = true
    end,
  },
}
