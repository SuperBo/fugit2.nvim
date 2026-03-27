---Fugit2 Stash list sub view

local NuiLine = require "nui.line"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"
local Object = require "nui.object"

---@class Fugit2StashListView
---@field ns_id integer
---@field popup NuiPopup
local StashListView = Object "Fugit2StashListView"

---@param ns_id integer
---@param entries StashEntry[]
function StashListView:init(ns_id, entries)
  self.ns_id = ns_id

  ---@type StashEntry[]
  self._entries = entries
  ---@type NuiLine[]
  self._lines = {}
  ---@type fun(action: string, entry: StashEntry)?
  self._action_fn = nil

  self.popup = NuiPopup {
    ns_id = ns_id,
    enter = true,
    focusable = true,
    relative = "editor",
    position = "50%",
    size = { width = 72, height = math.min(#entries, 15) },
    border = {
      style = "rounded",
      padding = { top = 0, bottom = 0, left = 1, right = 1 },
      text = {
        top = NuiText(" Stashes ", "Fugit2FloatTitle"),
        top_align = "left",
        bottom = NuiText(" a:apply  p:pop  d:drop  q:quit ", "FloatFooter"),
        bottom_align = "right",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = true,
      wrap = false,
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      buftype = "nofile",
      swapfile = false,
      filetype = "fugit2-stash",
    },
  }

  self:_build_lines()
end

---Builds NuiLine list from stash entries.
function StashListView:_build_lines()
  self._lines = {}
  for _, entry in ipairs(self._entries) do
    local line = NuiLine()
    line:append(string.format("stash@{%d}", entry.index), "Fugit2ObjectId")
    line:append("  ")
    line:append(entry.message)
    self._lines[#self._lines + 1] = line
  end
end

---Returns stash entry at cursor position.
---@param linenr integer?
---@return StashEntry? entry
function StashListView:get_entry(linenr)
  if not linenr then
    local winid = self.popup.winid
    if not winid or not vim.api.nvim_win_is_valid(winid) then
      return nil
    end
    linenr = vim.api.nvim_win_get_cursor(winid)[1]
  end
  return self._entries[linenr]
end

---Renders lines into buffer.
function StashListView:render()
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

---Replaces entries and re-renders.
---@param entries StashEntry[]
function StashListView:update(entries)
  self._entries = entries
  self:_build_lines()
  self.popup:update_layout { size = { width = 72, height = math.min(#entries, 15) } }
  self:render()
end

---Registers action callback.
---@param fn fun(action: string, entry: StashEntry)
function StashListView:on_action(fn)
  self._action_fn = fn
end

---Closes and unmounts the popup.
function StashListView:close()
  self.popup:unmount()
end

---Mounts popup and sets up keymaps.
function StashListView:mount()
  self.popup:mount()
  self:render()

  local opts = { noremap = true, nowait = true }

  self.popup:map("n", { "q", "<esc>" }, function()
    self:close()
  end, opts)

  self.popup:map("n", "a", function()
    local entry = self:get_entry()
    if entry and self._action_fn then
      self._action_fn("apply", entry)
    end
  end, opts)

  self.popup:map("n", "p", function()
    local entry = self:get_entry()
    if entry and self._action_fn then
      self._action_fn("pop", entry)
    end
  end, opts)

  self.popup:map("n", "d", function()
    local entry = self:get_entry()
    if entry and self._action_fn then
      self._action_fn("drop", entry)
    end
  end, opts)
end

return StashListView
