-- Boots a stripped Neovim with latex-nav-core and plenary on the rtp.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
