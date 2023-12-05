local Layout = require "nui.layout"
local NuiText = require "nui.text"
local Popup = require "nui.popup"

local NuiGitStatus = require "fugit2.view.nui_git_status"
local NuiGitGraph = require "fugit2.view.nui_git_graph"


---@classs Fugit2UIModule
local M = {}

-- Creates Fugit2 Main Floating Window
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@return NuiGitStatus
function M.new_fugit2_status_window(namespace, repo)
  local info_popup = Popup {
    enter = false,
    focusable = true,
    border = {
      style = "rounded",
      padding = {
        top = 1,
        bottom = 1,
        left = 2,
        right = 2,
      },
      text = {
        top = " Status ",
        top_align = "left",
      },
    },
    win_options = {
      winblend = 0,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      swapfile = false,
    },
  }

  local message_popup = Popup {
    enter = false,
    focusable = true,
    border = {
      style = "rounded",
      padding = {
        left = 1, right = 1
      },
      text = {
        top = NuiText(" Commit Message ", "Fugit2MessageHeading"),
        top_align = "left",
      }
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
    buf_options = {
      modifiable = true,
      filetype = "gitcommit",
      -- buftype = "prompt",
    }
  }

  local file_popup = Popup {
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
        top = " Files ",
        top_align = "left",
      },
    },
    win_options = {
      winblend = 0,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = true,
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      swapfile = false,
    },
  }

  -- Status content
  local status = NuiGitStatus(info_popup, file_popup, message_popup, namespace, repo)
  status:render()

  return status
end


-- Creates Fugit2 Graph floating window.
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@return NuiLayout
function M.new_fugit2_graph_window(namespace, repo)
  local branch_popup = Popup {
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

  local commit_popup = Popup {
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
  --
  -- local layout = Layout(
  --   {
  --     relative = "editor",
  --     position = "50%",
  --     size = {
  --       width = "80%",
  --       height = "80%",
  --     },
  --   },
  --   Layout.Box(
  --     {
  --       Layout.Box(branch_popup, { size = 30 }),
  --       Layout.Box(commit_popup, { grow = 1 }),
  --     },
  --     { dir = "row" }
  --   )
  -- )

  -- Status content
  local graph = NuiGitGraph(branch_popup, commit_popup, namespace, repo)
  graph:render()

  return graph
end


return M
