---Fugit2 keymap help popup view
---
---Renders a read-only list of keybindings for a view group. Pure UI component:
---it receives pre-resolved entries and performs no git operations.

local NuiLine = require "nui.line"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"
local Object = require "nui.object"

---@class Fugit2HelpEntry
---@field keys string display form of the binding, e.g. "D / x"
---@field desc string human-readable description
---@field mode string? mapping mode

---@class Fugit2HelpView
---@field ns_id integer
---@field popup NuiPopup
---@field _entries Fugit2HelpEntry[]
---@field _lines NuiLine[]
local HelpView = Object "Fugit2HelpView"

---@param ns_id integer
---@param title string popup title
---@param entries Fugit2HelpEntry[] resolved keymap entries for this view group
function HelpView:init(ns_id, title, entries)
  self.ns_id = ns_id
  self._title = title

  ---@type Fugit2HelpEntry[]
  self._entries = entries
  ---@type NuiLine[]
  self._lines = {}

  self.popup = NuiPopup {
    ns_id = ns_id,
    enter = true,
    focusable = true,
    relative = "editor",
    position = "50%",
    zindex = 55,
    size = { width = 60, height = math.min(#entries + 1, 20) },
    border = {
      style = "rounded",
      padding = { top = 0, bottom = 0, left = 1, right = 1 },
      text = {
        top = NuiText(" " .. title .. " ", "Fugit2FloatTitle"),
        top_align = "center",
        bottom = NuiText(" q/esc/? close ", "FloatFooter"),
        bottom_align = "right",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = false,
      wrap = false,
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      buftype = "nofile",
      swapfile = false,
      filetype = "fugit2-help",
    },
  }

  self:_build_lines()
end

---Builds NuiLine list from entries, right-padding keys for aligned descriptions.
function HelpView:_build_lines()
  self._lines = {}

  local key_width = 0
  for _, entry in ipairs(self._entries) do
    key_width = math.max(key_width, #entry.keys)
  end

  for _, entry in ipairs(self._entries) do
    local line = NuiLine()
    local keys = entry.keys
    if keys == "" then
      keys = "<disabled>"
    end
    line:append(string.format("%-" .. key_width .. "s", keys), "Fugit2HelpKey")
    line:append "  "
    line:append(entry.desc)
    self._lines[#self._lines + 1] = line
  end
end

---Renders lines into buffer.
function HelpView:render()
  local bufnr = self.popup.bufnr
  local ns_id = self.ns_id

  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(bufnr, "readonly", false)

  local lines = vim.tbl_map(function(l)
    return l:content()
  end, self._lines)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

  for i, l in ipairs(self._lines) do
    l:highlight(bufnr, ns_id, i)
  end

  vim.api.nvim_buf_set_option(bufnr, "readonly", true)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

---Closes and unmounts the popup.
function HelpView:close()
  if self.popup and self.popup.winid and vim.api.nvim_win_is_valid(self.popup.winid) then
    self.popup:unmount()
  end
end

---Mounts popup, renders and binds close keys.
function HelpView:mount()
  self.popup:mount()
  self:render()

  local opts = { noremap = true, nowait = true }
  self.popup:map("n", { "q", "<esc>", "?" }, function()
    self:close()
  end, opts)
end

return HelpView
