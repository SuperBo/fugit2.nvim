local GitDiff = require "fugit2.view.git_diff"
local GitGraph = require "fugit2.view.git_graph"
local GitStatus = require "fugit2.view.git_status"

---@classs Fugit2UIModule
local M = {}

local last_status_window = nil

-- Creates Fugit2 Main Floating Window
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@param opts Fugit2Config
---@return Fugit2GitStatusView
function M.new_fugit2_status_window(namespace, repo, opts)
  if last_status_window and not last_status_window.closed then
    return last_status_window
  end

  local current_win = vim.api.nvim_get_current_win()
  local current_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")

  local status = GitStatus(namespace, repo, current_win, current_file, opts)
  last_status_window = status
  return status
end

-- Creates Fugit2 Graph floating window.
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@return NuiLayout
function M.new_fugit2_graph_window(namespace, repo)
  -- Status content
  local graph = GitGraph(namespace, repo)
  graph:render()

  return graph
end

-- Creates Fugit2 DiffView tab.
---@param namespace integer Nvim namespace
---@return Fugit2GitDiffView
function M.new_fugit2_diff_view(namespace, repo)
  local diffview = GitDiff(namespace, repo, nil, nil)
  return diffview
end

return M
