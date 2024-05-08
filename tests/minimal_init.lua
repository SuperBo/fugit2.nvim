local on_windows = vim.loop.os_uname().version:match "Windows"

local function join_paths(...)
  local path_sep = on_windows and "\\" or "/"
  local result = table.concat({ ... }, path_sep)
  return result
end

local plenary_dir = os.getenv "PLENARY_DIR" or ".venv/plenary.nvim"
if vim.fn.isdirectory(plenary_dir) ~= 1 then
  vim.fn.system { "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir }
end

local nui_dir = os.getenv "NUI_DIR" or ".venv/nui.nvim"
if vim.fn.isdirectory(nui_dir) ~= 1 then
  vim.fn.system { "git", "clone", "https://github.com/MunifTanjim/nui.nvim", nui_dir }
end

vim.opt.rtp:append "."
vim.opt.rtp:append(plenary_dir)
vim.opt.rtp:append(nui_dir)

local libgit2 = require "fugit2.libgit2"
libgit2.load_library("libgit2")

vim.cmd "runtime plugin/plenary.vim"
require "plenary.busted"
