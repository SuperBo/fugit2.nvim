local NuiPopup = require "nui.popup"

local GitStatus = require "fugit2.view.git_status"
local GitGraph = require "fugit2.view.git_graph"


---@classs Fugit2UIModule
local M = {}

-- Creates Fugit2 Main Floating Window
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@return Fugit2GitStatusView
function M.new_fugit2_status_window(namespace, repo)
  local current_win = vim.api.nvim_get_current_win()
  local status = GitStatus(namespace, repo, current_win)
  status:render()
  return status
end


-- Creates Fugit2 Graph floating window.
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@return NuiLayout
function M.new_fugit2_graph_window(namespace, repo)
  local branch_popup = NuiPopup {
    enter = false,
    focusable = true,
    border = {
      style = "rounded",
      padding = {
        top = 0,
        bottom = 0,
        left = 1,
        right = 1,
      },
      text = {
        top = " Branches ",
        top_align = "left",
      },
    },
    win_options = {
      winblend = 0,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = true,
    },
    buf_options = {
      modifiable = true,
      readonly = false,
      swapfile = false,
    },
  }

  local commit_popup = NuiPopup {
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      padding = {
        top = 0,
        bottom = 0,
        left = 1,
        right = 1,
      },
      text = {
        top = " Commits ",
        top_align = "left",
      },
    },
    win_options = {
      winblend = 0,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = true,
    },
    buf_options = {
      -- modifiable = true,
      -- readonly = false,
      swapfile = false,
    },
  }

  -- Status content
  local graph = GitGraph(branch_popup, commit_popup, namespace, repo)
  graph:render()

  return graph
end


return M
