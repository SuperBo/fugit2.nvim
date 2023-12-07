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

  local width = math.max(msg_line:width(), 30)
  self._popup = NuiPopup {
    enter = true,
    focusable = true,
    position = "50%",
    size = {
      width = width,
      height = 2
    },
    border = {
      style = "single",
      padding = {
        left = 1,
        right = 1,
      },
      -- text = {
      --   top = " Status ",
      --   top_align = "left",
      -- },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      swapfile = false,
    },
  }

  -- content
  local title = NuiLine()
  title:append(string.rep(" ", math.floor((width - msg_line:width()) / 2)))
  title:append(msg_line)
  title:render(self._popup.bufnr, ns_id, 1)

  local yes_no_width = math.floor(width * 0.3)
  self._yes_pos = math.floor((width - yes_no_width) / 2)
  self._no_pos = self._yes_pos + yes_no_width - 2
  local yes_no = NuiLine {
    NuiText(string.rep(" ", self._yes_pos)),
    NuiText("Yes"),
    NuiText(string.rep(" ", yes_no_width - 5)),
    NuiText("No")
  }
  yes_no:render(self._popup.bufnr, ns_id, 2)

  -- handlers
  local exit_fn = function()
    self._popup:unmount()
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


---@param callback fun()
function Confirm:on_yes(callback)
  self._popup:map("n", "y", function()
    self._popup:unmount()
    callback()
  end)
  self._popup:map("n", "<cr>", function()
    local pos = vim.api.nvim_win_get_cursor(self._popup.winid)
    self._popup:unmount()
    if pos[1] == 2 and pos[2] < self._yes_pos + 4 then
      callback()
    end
  end)
end


function Confirm:mount()
  self._popup:mount()
  vim.api.nvim_win_set_cursor(self._popup.winid, { 2, self._yes_pos })
end

function Confirm:unmount()
  self._popup:unmount()
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
