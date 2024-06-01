-- Fugit2 main module file
local ui = require "fugit2.view.ui"

---@class Fugit2Config
---@field width integer|string main popup width
---@field max_width integer|string expand popup width
---@field min_width integer
---@field content_width integer
---@field height integer|string main file popup height
---@field libgit2_path string? path to libgit2 lib if not set via environments
---@field external_diffview boolean whether to use external diffview.nvim or Fugit2 implementation
local config = {
  width = 100,
  min_width = 50,
  content_width = 60,
  max_width = "80%",
  height = "60%",
  external_diffview = false,
}

---@class Fugit2Module
local M = {}

---@type integer
M.namespace = 0

---@type integer
M.autocmd_group = -1

---@type Fugit2Config
M.config = config

---@param args Fugit2Config?
-- Usually configurations can be merged, accepting outside params and
-- some validation here.
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  -- TODO: Validate

  -- Load C Library
  require("fugit2.git2").init(M.config.libgit2_path)

  if M.namespace == 0 then
    M.namespace = vim.api.nvim_create_namespace "Fugit2"
    require("fugit2.view.colors").set_hl(0)
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
    ui.new_fugit2_status_window(M.namespace, repo, M.config):mount()
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
    if #kwargs.fargs == 0 or kwargs.fargs[1] == "file" then
      ui.new_fugit2_blame_view(M.namespace, repo):mount()
    elseif kwargs.fargs[1] == "line" then
      --TODO
    end
  end
end

return M
