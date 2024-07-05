---@classs Fugit2UIModule
local M = {}

local last_status_window = nil
local last_graph_window = nil

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

  local GitStatus = require "fugit2.view.git_status"

  local status = GitStatus(namespace, repo, current_win, current_file, opts)
  last_status_window = status
  return status
end

-- Creates Fugit2 Graph floating window.
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@return NuiLayout
function M.new_fugit2_graph_window(namespace, repo)
  if last_graph_window and not last_graph_window.closed then
    return last_graph_window
  end

  -- Status content
  local GitGraph = require "fugit2.view.git_graph"
  local graph = GitGraph(namespace, repo)
  graph:render()
  last_graph_window = graph

  return graph
end

-- Creates Fugit2 DiffView tab.
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@return Fugit2GitDiffView
function M.new_fugit2_diff_view(namespace, repo)
  local GitDiff = require "fugit2.view.git_diff"
  local diffview = GitDiff(namespace, repo, nil, nil)
  return diffview
end

-- Creates Fugit2 BlameView
---@param namespace integer Nvim namespace
---@param repo GitRepository
function M.new_fugit2_blame_view(namespace, repo)
  local bufnr = vim.api.nvim_get_current_buf()
  local blameview = require "fugit2.view.git_blame"(namespace, repo, bufnr)
  return blameview
end

-- Creates Fugit2 BlameFile (inside buffer virtual text)
---@param namespace integer Nvim namespace
---@param repo GitRepository
function M.new_fugit2_blame_file(namespace, repo)
  local bufnr = vim.api.nvim_get_current_buf()
  local blame = require "fugit2.view.git_blame_file"(namespace, repo, bufnr)
  return blame
end

return M
