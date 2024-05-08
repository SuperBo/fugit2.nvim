-- Fugit2 main module file
local colors = require "fugit2.view.colors"
local libgit2 = require "fugit2.libgit2"

---@class Fugit2Config
---@field width integer|string main popup width
---@field max_width integer|string expand popup width
---@field min_width integer
---@field content_width integer
---@field height integer|string main file popup height
---@field libgit2_path string? path to libgit2 lib if not set via environments
local config = {
  width = 100,
  min_width = 50,
  content_width = 60,
  max_width = "80%",
  height = "60%",
}

---@class Fugit2Module
local M = {}

---@type number
M.namespace = 0

---@type Fugit2Config
M.config = config

---@param args Fugit2Config?
-- Usually configurations can be merged, accepting outside params and
-- some validation here.
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  -- Validate

  -- Load C Library
  libgit2.load_library(M.config.libgit2_path)

  if M.namespace == 0 then
    M.namespace = vim.api.nvim_create_namespace "Fugit2"
    colors.set_hl(0)
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
    local ui = require "fugit2.view.ui"
    ui.new_fugit2_status_window(M.namespace, repo, M.config):mount()
  end
end

function M.git_graph()
  local repo = open_repository()
  if repo then
    local ui = require "fugit2.view.ui"
    ui.new_fugit2_graph_window(M.namespace, repo):mount()
  end
end

function M.git_diff()
  local repo = open_repository()
  if repo then
    local ui = require "fugit2.view.ui"
    ui.new_fugit2_diff_view(M.namespace, repo):mount()
  end
end

return M
