-- Devbox: always show hidden files in Neovim and search menus
-- This file is copied to ~/.config/nvim/lua/config/ by devbox entrypoint

-- Netrw (built-in file browser): show hidden files
vim.g.netrw_hide = 0
vim.g.netrw_list_hide = "" -- Don't hide dotfiles (empty = show all)

-- Wildmenu (command-line completion): include hidden files
vim.opt.wildignore = vim.opt.wildignore:get() -- Keep default but we'll use suffixes
-- Show hidden in :e and similar
vim.opt.wildignorecase = true
-- Ensure dotfiles appear in file completion (wildmenu doesn't filter them by default if netrw is consistent)
vim.opt.fileignorecase = false
