-- Helper UI components for Fugit2
local NuiLine = require "nui.line"
local NuiMenu = require "nui.menu"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"
local Object = require "nui.object"
local event = require("nui.utils.autocmd").event

--=================
--| Confirm Popup |
--=================

---@class Fugit2UIConfirm
local Confirm = Object "Fugit2UIConfirm"

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
      height = 2,
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
      buftype = "nofile",
    },
  }

  self:set_text(msg_line)

  -- handlers
  local opts = { nowait = true, noremap = true }
  local exit_fn = function()
    self._popup:hide()
  end
  self._popup:on(event.BufLeave, exit_fn)
  self._popup:map("n", { "q", "n", "<esc>" }, exit_fn, opts)
  self._popup:map("n", "l", function()
    vim.api.nvim_win_set_cursor(self._popup.winid, { 2, self._no_pos })
  end, opts)
  self._popup:map("n", "h", function()
    vim.api.nvim_win_set_cursor(self._popup.winid, { 2, self._yes_pos })
  end, opts)
  self._popup:map("n", "<tab>", function()
    local pos = vim.api.nvim_win_get_cursor(self._popup.winid)
    local new_pos = (pos[2] < self._yes_pos + 4) and self._no_pos or self._yes_pos
    vim.api.nvim_win_set_cursor(self._popup.winid, { 2, new_pos })
  end, opts)
end

---@parm text NuiLine
function Confirm:set_text(text)
  local width = math.max(text:width(), 30)

  self._popup:update_layout {
    position = "50%",
    size = { width = width, height = 2 },
  }

  vim.api.nvim_buf_set_option(self._popup.bufnr, "readonly", false)

  -- content
  local title = NuiLine()
  title:append(string.rep(" ", math.floor((width - text:width()) / 2)))
  title:append(text)
  title:render(self._popup.bufnr, self.ns_id, 1)

  local yes_no_width = math.max(math.floor(width * 0.3), 10)
  self._yes_pos = math.floor((width - yes_no_width) / 2)
  self._no_pos = self._yes_pos + yes_no_width - 2
  local yes_no = NuiLine {
    NuiText(string.rep(" ", self._yes_pos - 1)),
    NuiText("󰄬 Yes", "Fugit2Staged"),
    NuiText(string.rep(" ", yes_no_width - 9)),
    NuiText("󰜺 No", "Fugit2Untracked"),
  }
  yes_no:render(self._popup.bufnr, self.ns_id, 2)

  vim.api.nvim_buf_set_option(self._popup.bufnr, "readonly", true)
end

---@param callback function
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

---@param callback function
function Confirm:on_exit(callback)
  self._popup:on(event.BufHidden, callback)
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

---@enum Fugit2UITransientInputType
local INPUT_TYPE = {
  CHECKBOX = 1,
  RADIO = 2,
}

---@class Fugit2UITransientMenu
---@field _menu NuiMenu
---@field ns_id integer
local Menu = Object "Fugit2UITransientMenu"

---@alias Fugit2UITransientArg { key: string, text: NuiText, arg: string, type: Fugit2UITransientInputType, model: string, default: boolean?}
---@alias Fugit2UITransientItem { key: string?, texts: NuiText[] }
---@alias Fugit2UITransientArgModel { [string]: string[] }

---@param ns_id integer namespace id
---@param title NuiText Menu title
---@param menu_items Fugit2UITransientItem[]
---@param arg_items Fugit2UITransientArg[]?
function Menu:init(ns_id, title, menu_items, arg_items)
  self.ns_id = ns_id
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
    },
  }

  local menu_lines = vim.tbl_map(function(item)
    if not item.key then
      return NuiMenu.separator(NuiLine(item.texts), menu_item_align)
    end
    local texts = { NuiText(item.key .. "  ", key_hl) }
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
  self._args = {} -- store args value
  ---@type { [string]: integer }
  self._arg_indices = {} -- mapping from arg name to index in arg_items
  ---@type { [string]: { type: Fugit2UITransientInputType, keys: string[] } }
  self._arg_models = {}
  if arg_items then
    local arg_popup_opts = {
      ns_id = ns_id,
      enter = false,
      relative = "win",
      position = {
        row = #menu_items + 2,
        col = 0,
      },
      size = {
        width = popup_opts.size.width,
        height = #arg_items,
      },
      focusable = false,
      border = {
        style = "single",
        text = { top = NuiText(" Arguments ", key_hl), top_align = "left" },
      },
      zindex = popup_opts.zindex,
      win_options = popup_opts.win_options,
    }
    self._args_popup = NuiPopup(arg_popup_opts)

    self._arg_items = arg_items
    for i, item in ipairs(arg_items) do
      self._args[item.key] = item.default or false
      self._arg_indices[item.key] = i

      if not self._arg_models[item.model] then
        self._arg_models[item.model] = { type = item.type, keys = {} }
      end
      table.insert(self._arg_models[item.model].keys, item.key)
    end
  end

  -- setup hotkey
  local ids = vim.tbl_filter(function(n)
    return n.key ~= nil
  end, menu_items)
  self._hotkeys = vim.tbl_map(function(n)
    return n.key
  end, ids)
end

---@param item Fugit2UITransientArg
---@param enabled boolean
---@return NuiLine
local function arg_item_to_line(item, enabled)
  local line = NuiLine { NuiText(item.key .. " ", "Fugit2MenuKey") }
  if enabled and item.type == INPUT_TYPE.CHECKBOX then
    line:append("󰄵 ", "Fugit2MenuArgOn")
  elseif enabled and item.type == INPUT_TYPE.RADIO then
    line:append("󰄴 ", "Fugit2MenuArgOn")
  elseif item.type == INPUT_TYPE.CHECKBOX then
    line:append("󰄱 ", "Fugit2MenuArgOff")
  elseif item.type == INPUT_TYPE.RADIO then
    line:append("󰝦 ", "Fugit2MenuArgOff")
  end
  line:append(item.text)
  line:append(" " .. item.arg, enabled and "Fugit2MenuArgOn" or "Fugit2MenuArgOff")
  return line
end

-- Render args selection
function Menu:render()
  for i, item in ipairs(self._arg_items) do
    local line = arg_item_to_line(item, self._args[item.key])
    line:render(self._args_popup.bufnr, self.ns_id, i)
  end
end

---@param args { [string]: boolean }
---@param arg_models { [string]: { type: Fugit2UITransientInputType, keys: string[] } }
---@param arg_indices { [string]: integer }
---@param arg_items { [string]: Fugit2UITransientArg[] }
---@return Fugit2UITransientArgModel
local function collect_args(args, arg_models, arg_indices, arg_items)
  return vim.tbl_map(function(m)
    local values = {}
    if m.type == INPUT_TYPE.CHECKBOX then
      for _, k in ipairs(m.keys) do
        if args[k] then
          values[#values + 1] = arg_items[arg_indices[k]].arg
        end
      end
    elseif m.type == INPUT_TYPE.RADIO then
      for _, k in ipairs(m.keys) do
        if args[k] then
          values[1] = arg_items[arg_indices[k]].arg
          break
        end
      end
    end
    return values
  end, arg_models)
end

---Set call back func
---@param callback fun(item_id: string, args: Fugit2UITransientArgModel)
function Menu:on_submit(callback)
  self._submit_fn = callback
  self._menu.menu_props.on_submit = function()
    local item_id = self._menu.tree:get_node().id or ""
    self._menu:unmount()
    local args = collect_args(self._args, self._arg_models, self._arg_indices, self._arg_items)
    self._submit_fn(item_id, args)
  end
end

function Menu:mount()
  self._menu:mount()
  for _, key in ipairs(self._hotkeys) do
    self._menu:map("n", key, function()
      self._menu:unmount()
      local args = collect_args(self._args, self._arg_models, self._arg_indices, self._arg_items)
      self._submit_fn(key, args)
    end, { noremap = true, nowait = true })
  end

  -- prevent inconvenience with oil nvim
  self._menu:map("n", "-", "", { noremap = true })

  if self._args_popup then
    self._menu:on(event.BufHidden, function()
      self._args_popup:unmount()
    end)

    self._args_popup:update_layout {
      relative = {
        type = "win",
        winid = self._menu.winid,
      },
    }
    self._args_popup:mount()

    for _, item in pairs(self._arg_items) do
      -- reset setting to default
      self._args[item.key] = item.default or false

      -- map arg keys
      local arg = item.key
      self._menu:map("n", arg, function()
        local enabled = not self._args[arg]
        self._args[arg] = enabled
        local i = self._arg_indices[arg]

        local line = arg_item_to_line(self._arg_items[i], enabled)
        line:render(self._args_popup.bufnr, self.ns_id, i)

        if self._arg_items[i].type == INPUT_TYPE.RADIO then
          -- turn off other flags
          local model = self._arg_models[self._arg_items[i].model]
          if model then
            for _, a in ipairs(model.keys) do
              if a ~= arg and self._args[a] then
                self._args[a] = false
                local j = self._arg_indices[a]
                local linej = arg_item_to_line(self._arg_items[j], false)
                linej:render(self._args_popup.bufnr, self.ns_id, j)
              end
            end
          end
        end
      end, { noremap = true, nowait = true })
    end

    self:render()
  end
end

function Menu:unmount()
  self._menu:unmount()
end

---@module 'Fugit2UIComponents'
local M = {
  Confirm = Confirm,
  Menu = Menu,
  INPUT_TYPE = INPUT_TYPE,
}

return M
