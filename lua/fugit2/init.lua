-- Fugit2 main module file
local config = require "fugit2.config"
local ui = require "fugit2.view.ui"

---@class Fugit2Module
local M = {}

---@type integer
M.namespace = 0

---@type integer
M.autocmd_group = -1

---@param args Fugit2Config?
-- Usually configurations can be merged, accepting outside params and
-- some validation here.
M.setup = function(args)
  local cfg = config.merge(args)

  -- Load C Library
  require("fugit2.git2").init(cfg.libgit2_path)
  require("fugit2.core.gpgme").init(cfg.gpgme_path)

  if M.namespace == 0 then
    M.namespace = vim.api.nvim_create_namespace "Fugit2"
    require("fugit2.view.colors").set_hl(0, cfg.colorscheme)
  end

  if M.autocmd_group < 0 then
    M.autocmd_group = vim.api.nvim_create_augroup("Fugit2", { clear = true })
  end
end

---@type { [string]: GitRepository }
local repos = {}

---@return GitRepository?
local function open_repository()
  local cwd = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p:h")

  ---@type GitRepository?
  local repo = repos[cwd]

  if not repo then
    local git2 = require "fugit2.git2"

    local err
    repo, err = git2.Repository.open(cwd, true)
    if repo then
      -- repos[cwd] = repo
      local repo_path = vim.fn.fnamemodify(repo:repo_path(), ":p:h:h")

      while repo_path:len() <= cwd:len() do
        repos[cwd] = repo
        cwd = vim.fn.fnamemodify(cwd, ":h")
      end
    else
      vim.notify(string.format("Can't open git directory at %s, error code: %d", cwd, err), vim.log.levels.WARN)
      return nil
    end
  end

  return repo
end

function M.git_status()
  local repo = open_repository()
  if repo then
    local cfg = config.config
    ui.new_fugit2_status_window(M.namespace, repo, cfg):mount()
  end
end

function M.git_graph()
  local repo = open_repository()
  if repo then
    ui.new_fugit2_graph_window(M.namespace, repo):mount()
  end
end

---@param kwargs table arguments table
function M.git_diff(kwargs)
  local repo = open_repository()
  if repo then
    local diffview = ui.new_fugit2_diff_view(M.namespace, repo)
    diffview:mount()
    if #kwargs.fargs > 0 then
      diffview:focus_file(kwargs.fargs[1])
    end
  end
end

---@param kwargs table arguments table
function M.git_blame(kwargs)
  local repo = open_repository()
  if repo then
    if #kwargs.fargs == 0 or kwargs.fargs[1] ~= "split" then
      if kwargs.fargs[1] == "toggle" or kwargs.fargs[2] == "toggle" then
        ui.new_fugit2_blame_file(M.namespace, repo):toggle()
      else
        ui.new_fugit2_blame_file(M.namespace, repo):refresh()
      end
    elseif kwargs.fargs[1] == "split" then
      ui.new_fugit2_blame_view(M.namespace, repo):mount()
    end
  end
end

return M
