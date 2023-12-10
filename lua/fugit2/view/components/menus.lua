-- Helper UI components for Fugit2
local Object = require "nui.object"
local NuiText = require "nui.text"
local NuiLine = require "nui.line"
local NuiMenu = require "nui.menu"
local NuiPopup = require "nui.popup"
local event = require("nui.utils.autocmd").event

--=================
--| Confirm Popup |
--=================

---@class Fugit2UIConfirm
local Confirm = Object("Fugit2UIConfirm")


---@param ns_id integer Namespace id
---@param msg_line NuiLine Message for confirm popup
function Confirm:init(ns_id, msg_line)
  self.ns_id = ns_id

  self._popup = NuiPopup {
    enter = true,
    focusable = true,
    relative = "editor",
    position = "50%",
    size = {
      width = 30,
      height = 2
    },
    zindex = 55,
    border = {
      style = "single",
      padding = {
        left = 1,
        right = 1,
      },
      text = {
        top = "Confirm",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
    buf_options = {
      modifiable = true,
      readonly = true,
      swapfile = false,
    },
  }

  self:set_text(msg_line)

    -- handlers
  local exit_fn = function()
    self._popup:hide()
  end
  self._popup:on(event.BufLeave, exit_fn)
  self._popup:map("n", "q", exit_fn)
  self._popup:map("n", "n", exit_fn)
  self._popup:map("n", "<esc>", exit_fn)
  self._popup:map("n", "l", function()
    vim.api.nvim_win_set_cursor(self._popup.winid, { 2, self._no_pos })
  end)
  self._popup:map("n", "h", function()
    vim.api.nvim_win_set_cursor(self._popup.winid, { 2, self._yes_pos })
  end)
end


---@parm text NuiLine
function Confirm:set_text(text)
  local width = math.max(text:width(), 30)

  self._popup:update_layout({
    position = "50%",
    size = { width = width, height = 2 }
  })

  vim.api.nvim_buf_set_option(self._popup.bufnr, "readonly", false)

  -- content
  local title = NuiLine()
  title:append(string.rep(" ", math.floor((width - text:width()) / 2)))
  title:append(text)
  title:render(self._popup.bufnr, self.ns_id, 1)

  local yes_no_width = math.floor(width * 0.3)
  local yes_width, no_width = 5, 4
  self._yes_pos = math.floor((width - yes_no_width) / 2)
  self._no_pos = self._yes_pos + yes_no_width - no_width
  local yes_no = NuiLine {
    NuiText(string.rep(" ", self._yes_pos)),
    NuiText("󰄬 Yes", "Fugit2Staged"),
    NuiText(string.rep(" ", self._no_pos - self._yes_pos - yes_width - no_width)),
    NuiText("󰜺 No", "Fugit2Untracked")
  }
  yes_no:render(self._popup.bufnr, self.ns_id, 2)

  vim.api.nvim_buf_set_option(self._popup.bufnr, "readonly", true)
end

---@param callback fun()
function Confirm:on_yes(callback)
  self._popup:map("n", "y", function()
    self._popup:hide()
    callback()
  end, { noremap = true, nowait = true })
  self._popup:map("n", "<cr>", function()
    local pos = vim.api.nvim_win_get_cursor(self._popup.winid)
    self._popup:hide()
    if pos[1] == 2 and pos[2] < self._yes_pos + 4 then
      callback()
    end
  end, { noremap = true, nowait = true })
end

function Confirm:mount()
  self._popup:mount()
  vim.api.nvim_win_set_cursor(self._popup.winid, { 2, self._yes_pos })
end

function Confirm:unmount()
  self._popup:unmount()
end

function Confirm:hide()
  self._popup:hide()
end

function Confirm:show()
  self._popup:show()
  vim.api.nvim_win_set_cursor(self._popup.winid, { 2, self._yes_pos })
end


--==============
--| Menu Popup |
--==============


---@class Fugit2UIMenu
---@field _menu NuiMenu
local Menu = Object("Fugit2UIMenu")


---@param popup_opts nui_popup_options
---@param lines NuiTree.Node[]
function Menu:init(popup_opts, lines)
  self._menu = NuiMenu(popup_opts, {
    lines = lines,
    keymap = {
      focus_next = { "j", "<down>", "<tab>", "<c-n>" },
      focus_prev = { "k", "<up>", "<s-tab>", "<c-p>" },
      close = { "<esc>", "<c-c>", "q" },
      submit = { "<cr>", "<Space>" },
    },
  })

  -- setup hotkey
  local ids = vim.tbl_filter(
    function (n) return n.id ~= nil end, lines
  )
  self._hotkeys = vim.tbl_map(
    function (n) return n.id end, ids
  )
end


---Set call back func
---@param callback fun(string)
function Menu:on_submit(callback)
  self._submit_fn = callback
  self._menu.menu_props.on_submit = function()
    local item_id = self._menu.tree:get_node().id or ""
    self._menu:unmount()
    self._submit_fn(item_id)
  end
end


function Menu:mount()
  self._menu:mount()
  for _, key in ipairs(self._hotkeys) do
    self._menu:map("n", key, function()
      self._menu:unmount()
      self._submit_fn(key)
    end, { noremap = true, nowait = true })
  end
end


function Menu:unmount()
  self._menu:unmount()
end


---@module 'Fugit2UIComponents'
local M = {
  Confirm = Confirm,
  Menu = Menu
}

return M
