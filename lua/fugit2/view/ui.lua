local Layout = require "nui.layout"
local Popup = require "nui.popup"

local NuiGitStatus = require "fugit2.view.nui_git_status"
local NuiGitGraph = require "fugit2.view.nui_git_graph"


---@classs Fugit2UIModule
local M = {}

-- Creates Fugit2 Main Floating Window
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@return NuiLayout
function M.new_fugit2_status_window(namespace, repo)

  local popup_one = Popup {
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

  local popup_two = Popup {
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

  local layout = Layout(
    {
      relative = "editor",
      position = "50%",
      size = {
        width = "80%",
        height = "60%",
      },
    },
    Layout.Box({
      Layout.Box(popup_one, { size = 6 }),
      Layout.Box(popup_two, { grow = 1 }),
    }, { dir = "col" })
  )

  -- Exit event
  local exit_fn = function()
    layout:unmount()
  end
  local map_options = { noremap = true }

  popup_one:map("n", "q", exit_fn, map_options)
  popup_one:map("n", "<esc>", exit_fn, map_options)
  -- popup_two:on(event.BufLeave, exit_fn)

  -------------
  -- Content --
  -------------

  -- Status content
  local status = NuiGitStatus(popup_one.bufnr, popup_two.bufnr, namespace, repo)
  status:setup_handlers(popup_two, map_options)
  status:render()

  return layout
end


-- Creates Fugit2 Graph floating window.
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@return NuiLayout
function M.new_fugit2_graph_window(namespace, repo)
  local branch_popup = Popup {
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

  local layout = Layout(
    {
      relative = "editor",
      position = "50%",
      size = {
        width = "80%",
        height = "80%",
      },
    },
    Layout.Box(
      {
        Layout.Box(branch_popup, { size = 30 }),
        Layout.Box(commit_popup, { grow = 1 }),
      },
      { dir = "row" }
    )
  )

  -- Status content
  local graph = NuiGitGraph(branch_popup.bufnr, commit_popup.bufnr, namespace, repo)
  graph:setup_handlers(branch_popup, commit_popup, { noremap = true })
  graph:render()

  return layout
end


return M
