local NuiLine = require "nui.line"
local NuiMenu = require "nui.menu"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"

local NuiGitStatus = require "fugit2.view.nui_git_status"
local NuiGitGraph = require "fugit2.view.nui_git_graph"


---@classs Fugit2UIModule
local M = {}

-- Creates Fugit2 Main Floating Window
---@param namespace integer Nvim namespace
---@param repo GitRepository
---@return NuiGitStatus
function M.new_fugit2_status_window(namespace, repo)
  local info_popup = NuiPopup {
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
      modifiable = true,
      readonly = false,
      swapfile = false,

    },
  }

  local message_popup = NuiPopup {
    enter = false,
    focusable = true,
    border = {
      style = "rounded",
      padding = {
        left = 1, right = 1
      },
      text = {
        top = NuiText(" Create commit ", "Fugit2MessageHeading"),
        top_align = "left",
        bottom = NuiText("[ctrl-c][esc][q]uit, [enter]", "FloatFooter"),
        bottom_align = "right",
      }
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
    buf_options = {
      modifiable = true,
      filetype = "gitcommit",
    }
  }

  local file_popup = NuiPopup {
    enter = true,
    focusable = true,
    zindex = 50,
    border = {
      style = "rounded",
      padding = {
        top = 0,
        bottom = 0,
        left = 1,
        right = 1,
      },
      text = {
        top = " 󰙅 Files ",
        top_align = "left",
        bottom = NuiText("[c]ommits", "FloatFooter"),
        bottom_align = "right",
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

  local menu_item_align = { text_align = "center" }
  local commit_menu = NuiMenu(
    {
      position = "50%",
      size = {
        width = 36,
        height = 8,
      },
      zindex = 52,
      border = {
        style = "single",
        text = {
          top = "Commit Menu",
          top_align = "left",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:Normal",
      },
    },
    {
      lines = {
        NuiMenu.separator(
          NuiText("Create", "Fugit2MenuHead"),
          menu_item_align
        ),
        NuiMenu.item(NuiLine({NuiText("c ", "Fugit2MenuKey"), NuiText("Commit")}), { id = "c" }),
        NuiMenu.separator(
          NuiLine { NuiText("Edit ", "Fugit2MenuHead"), NuiText("HEAD", "Fugit2Staged") },
          menu_item_align
        ),
        NuiMenu.item(NuiLine { NuiText("e ", "Fugit2MenuKey"), NuiText("Extend") }, { id = "e" }),
        NuiMenu.item(NuiLine { NuiText("r ", "Fugit2MenuKey"), NuiText("Reword") }, { id = "r" }),
        NuiMenu.item(NuiLine { NuiText("a ", "Fugit2MenuKey"), NuiText("Amend") }, { id = "a" }),
        NuiMenu.separator(
          NuiText("View/Edit", "Fugit2MenuHead"),
          menu_item_align
        ),
        NuiMenu.item(NuiLine { NuiText("g ", "Fugit2MenuKey"), NuiText("Graph") }, { id = "g" }),
      },
      keymap = {
        focus_next = { "j", "<down>", "<tab>", "<c-n>" },
        focus_prev = { "k", "<up>", "<s-tab>", "<c-p>" },
        close = { "<esc>", "<c-c>", "q" },
        submit = { "<cr>", "<Space>" },
      },
      on_close = function()
      end,
      on_submit = nil,
    }
  )

  -- Status content
  local status = NuiGitStatus(namespace, repo, info_popup, file_popup, message_popup, commit_menu)
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
  local graph = NuiGitGraph(branch_popup, commit_popup, namespace, repo)
  graph:render()

  return graph
end


return M
