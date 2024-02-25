-- Fugit2 main module file
local colors = require "fugit2.view.colors"
local git2 = require "fugit2.git2"
local ui = require "fugit2.view.ui"

---@class Config
---@field opt string Default config option
local config = {
  opt = "Hello!",
}

---@class Fugit2Module
local M = {}

---@type number
M.namespace = 0

---@type Config
M.config = config

---@param args Config?
-- Usually configurations can be merged, accepting outside params and
-- some validation here.
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  -- Validate

  if M.namespace == 0 then
    M.namespace = vim.api.nvim_create_namespace "Fugit2"
    colors.set_hl(0)
  end
end

---@type { [string]: GitRepository }
local repos = {}

---@return GitRepository?
local function open_repository()
  local cwd = vim.fn.getcwd()
  ---@type GitRepository?
  local repo = repos[cwd]

  if not repo then
    local err
    repo, err = git2.Repository.open(cwd, true)
    if repo then
      repos[cwd] = repo
      if repo:repo_path() ~= cwd then
        repos[repo:repo_path()] = repo
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
    ui.new_fugit2_status_window(M.namespace, repo):mount()
  end
end

function M.git_graph()
  local repo = open_repository()
  if repo then
    ui.new_fugit2_graph_window(M.namespace, repo):mount()
  end
end

function M.git_diff()
  local repo = open_repository()
  if repo then
    ui.new_fugit2_diff_view(M.namespace, repo):mount()
  end
end

return M
