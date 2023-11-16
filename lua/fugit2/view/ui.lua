local NuiLine = require "nui.line"
local NuiText = require "nui.text"
local Popup = require "nui.popup"
local event = require "nui.utils.autocmd".event

local git2 = require "fugit2.git2"


-- Reads git status and convert to buffer content
---@param bufnr number Buffer number
---@param ns number Nvim namespace number
---@param repo GitRepository Git2 repository
local render_git2_status = function(bufnr, ns, repo)
  local line = NuiLine()
  line:append('  ')
  line:append(string.rep('  ', 10))
  local status, error = git2.status(repo)

  if status == nil then
    NuiText("Git2 Error Code: " .. error, "Error"):render(bufnr, ns, 1, 0)
    return
  end


  ---@type string
  local status_str

  line:append("Worktree")

  for _, item in ipairs(status.worktree) do
    status_str = git2.GIT_STATUS_SHORT.tostring(item.status)
    if item.new_path then
      line:append(
        string.format("- %s: %s -> %s", status_str, item.path, item.new_path)
      )
    else
      line:append(
        string.format("- %s: %s", status_str, item.path)
      )
    end
  end

  line:append("")
  line:append("Staging")

  for _, item in ipairs(status.index) do
    status_str = git2.GIT_STATUS_SHORT.tostring(item.status)
    if item.new_path then
      line:append(
        string.format("- %s: %s -> %s", status_str, item.path, item.new_path)
      )
    else
      line:append(
        string.format("- %s: %s", status_str, item.path)
      )
    end
  end

  line:render(bufnr, ns, 1)
end


---@classs Fugit2UIModule
local M = {}

-- Create Fugit2 Floating Window
---@param ns number Nvim namespace
---@param repo GitRepository
---@return NuiPopup
function M.new_fugit2_float_window(ns, repo)
  local popup = Popup({
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
        top = " Fugit2 ",
        top_align = "left",
      },
    },
    relative = "editor",
    position = "50%",
    size = {
      width = "80%",
      height = "60%",
    },
    win_options = {
      winblend = 10,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  })

  -- Exit event
  local exit_fn = function()
    popup:unmount()
  end

  popup:on(event.BufLeave, exit_fn)
  popup:map("n", "q", exit_fn)

  -------------
  -- Content --
  -------------

  -- Status content
  render_git2_status(popup.bufnr, ns, repo)

  local line = NuiLine()
  line:append(NuiLine({NuiText("Text 1")}))
  line:append(NuiLine({NuiText("Text 2")}))
  line:render(popup.bufnr, -1, 11)

  return popup
end


return M
