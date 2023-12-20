-- Helper UI components for Fugit2
local Object = require "nui.object"
local NuiText = require "nui.text"
local NuiLine = require "nui.line"
local NuiMenu = require "nui.menu"
local NuiPopup = require "nui.popup"
local NuiLayout = require "nui.layout"
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
      buftype  = "nofile",
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


--========================
--| Transient Menu Popup |
--=======================


---@class Fugit2UITransientMenu
---@field _menu NuiMenu
---@field ns_id integer
local Menu = Object("Fugit2UITransientMenu")

---@alias Fugit2UITransientArg { key: string, text: NuiText, arg: string }
---@alias Fugit2UITransientItem { key: string?, texts: NuiText[] }

---@param ns_id integer namespace id
---@param title NuiText Menu title
---@param menu_items Fugit2UITransientItem[]
---@param arg_items Fugit2UITransientArg[]?
function Menu:init(ns_id, title, menu_items, arg_items)
  self.ns_id = ns_id
  local title_hl = "Fugit2FloatTitle"
  local head_hl = "Fugit2MenuHead"
  local key_hl = "Fugit2MenuKey"
  local menu_item_align = { text_align = "center" }
  local popup_opts = {
    ns_id = ns_id,
    enter = true,
    position = "50%",
    relative = "editor",
    size = {
      width = 40,
    },
    zindex = 52,
    border = {
      style = "single",
      text = {
        top = title,
        top_align = "left",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    }
  }

  local menu_lines = vim.tbl_map(function(item)
    if not item.key then
      return NuiMenu.separator(NuiLine(item.texts), menu_item_align)
    end
    local texts = { NuiText(item.key .. " ", key_hl) }
    vim.list_extend(texts, item.texts)
    return NuiMenu.item(NuiLine(texts), { id = item.key })
  end, menu_items)

  self._menu = NuiMenu(popup_opts, {
    lines = menu_lines,
    keymap = {
      focus_next = { "j", "<down>", "<tab>", "<c-n>" },
      focus_prev = { "k", "<up>", "<s-tab>", "<c-p>" },
      close = { "<esc>", "<c-c>", "q" },
      submit = { "<cr>", "<Space>" },
    },
  })

  ---@type { [string]: boolean }
  self._args = {}
  self._arg_lines = {}
  self._arg_indices = {}
  if arg_items then
    local arg_popup_opts = {
      ns_id = ns_id,
      enter = false,
      relative = "win",
      position = {
        row = #menu_items + 2,
        col = 0
      },
      size = {
        width = popup_opts.size.width,
        height = #arg_items,
      },
      focusable = false,
      border = {
        style = "single",
        text = { top = NuiText(" Arguments ", key_hl), top_align = "left" }
      },
      zindex = popup_opts.zindex,
      win_options = popup_opts.win_options
    }
    self._args_popup = NuiPopup(arg_popup_opts)

    self._arg_items = arg_items
    for i, item in ipairs(arg_items) do
      self._args[item.key] = false
      self._arg_indices[item.key] = i
    end
  end

  -- setup hotkey
  local ids = vim.tbl_filter(
    function (n) return n.key ~= nil end, menu_items
  )
  self._hotkeys = vim.tbl_map(
    function(n) return n.key end, ids
  )

end

---@param item Fugit2UITransientArg
---@param enabled boolean
---@return NuiLine
local function arg_item_to_line(item, enabled)
  local line = NuiLine { NuiText(item.key .. " ", "Fugit2MenuKey") }
  if enabled then
    line:append("󰱒 ", "Fugit2MenuArgOn")
  else
    line:append("󰄱 ", "Fugit2MenuArgOff")
  end
  line:append(item.text)
  -- line:append(" (")
  line:append(" " .. item.arg, enabled and "Fugit2MenuArgOn" or "Fugit2MenuArgOff")
  -- line:append(")")
  return line
end

---Render args selection
function Menu:render()
  for i, item in ipairs(self._arg_items) do
    local line = arg_item_to_line(item, false)
    line:render(self._args_popup.bufnr, self.ns_id, i)
  end
end


---Set call back func
---@param callback fun(item_id: string, args: { [string]: boolean })
function Menu:on_submit(callback)
  self._submit_fn = callback
  self._menu.menu_props.on_submit = function()
    local item_id = self._menu.tree:get_node().id or ""
    self._menu:unmount()
    self._submit_fn(item_id, self._args)
  end
end


function Menu:mount()
  self._menu:mount()
  for _, key in ipairs(self._hotkeys) do
    self._menu:map("n", key, function()
      self._menu:unmount()
      self._submit_fn(key, self._args)
    end, { noremap = true, nowait = true })
  end

  if self._args_popup then
    self._menu:on(event.BufHidden, function()
      self._args_popup:unmount()
    end)

    self._args_popup:update_layout({
      relative = {
        type = "win",
        winid = self._menu.winid,
      },
    })
    self._args_popup:mount()
    self:render()

    for arg, _ in pairs(self._args) do
      self._args[arg] = false
      self._menu:map("n", arg, function()
        local enabled = not self._args[arg]
        self._args[arg] = enabled
        local i = self._arg_indices[arg]

        local line = arg_item_to_line(self._arg_items[i], enabled)
        line:render(self._args_popup.bufnr, self.ns_id, i)
      end, { noremap = true, nowait = true })
    end
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
