local NuiText = require "nui.text"
local NuiLine = require "nui.line"
local NuiPopup = require "nui.popup"
local Object = require "nui.object"
local event = require "nui.utils.autocmd".event

local diff = require "fugit2.diff"


---@class Fugit2PatchView
---@field ns_id integer namespace id
---@field popup NuiPopup
---@field tree NuiTree
local PatchView = Object("Fugit2PatchView")


---@param ns_id integer
---@param title string
function PatchView:init(ns_id, title)
  self.ns_id = ns_id

  -- popup
  self.popup = NuiPopup {
    position = "50%",
    size = {
      width = 80,
      height = 40,
    },
    enter = false,
    focusable = true,
    border = {
      padding = {
        left = 1,
        right = 1,
      },
      style = "rounded",
      text = {
        top = title,
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      filetype = "diff",
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = true,
    },
  }

  -- sub components
  self._header = {}
  self._hunks = {}

  self.popup:on(event.BufEnter, function()
    -- to avoid conflict with vim-ufo
    if vim.fn.exists(':UfoDetach') > 0 then
      vim.cmd("UfoDetach")
    end
    vim.api.nvim_win_set_option(self.popup.winid, "foldmethod", "expr")
    vim.api.nvim_win_set_option(self.popup.winid, "foldexpr", "Fugit2DiffFold(v:lnum)")
  end, { once = true })

  -- keymaps
  local opts = { noremap = true, nowait = true }
  self.popup:map("n", "=", "za", opts)
  self.popup:map("n", "]", self:next_hunk_handler(), opts)
  self.popup:map("n", "[", self:prev_hunk_handler(), opts)
  -- local expand_collapse_handler = self:expand_collapse_handler()
  -- self.popup:map("n", "<cr>", expand_collapse_handler, opts)
  -- self.popup:map("n", "l", self:expand_handler(), opts)
  -- self.popup:map("n", "H", self:collapse_all_handler(), opts)
  -- self.popup:map("n", "L", self:expand_all_handler(), opts)
end

---@param node NuiTree.Node
---@return NuiLine
local function tree_prepare_node(node)
  local line = NuiLine()
  local extmark

  if node:has_children() then
    -- line:append(node:is_expanded() and " " or " ")
    if not node:is_expanded() then
      extmark = "Visual"
    end
  elseif node.c == " " or node.c == "" then
    if node.last_line then
      local whitespace = node.text:match("%s+")
      local whitespace_len = whitespace and whitespace:len() - 1 or 0
      line:append("", {
        virt_text = {{"└" .. string.rep("─", whitespace_len), "Whitespace"}},
        virt_text_pos = "overlay",
      })
    else
      line:append("", {
        virt_text = {{"│", "LineNr"}},
        virt_text_pos = "overlay",
      })
    end
  end

  line:append(node.text, extmark)
  return line
end

---Updates content with a given patch
---@param patch_item GitDiffPatchItem
function PatchView:update(patch_item)
  local patch = patch_item.patch
  local header, hunks = {}, {}

  local lines = vim.split(tostring(patch), "\n", { plain=true, trimempty=true })

  for i, l in ipairs(lines) do
    if l:sub(1, 1) ~= "@" then
      header[i] = l
    else
      hunks[1] = i
      break
    end
  end

  local line_num = hunks[1]
  local num_hunks = tonumber(patch:nhunks())
  for i = 0,num_hunks-1 do
    line_num = line_num + patch:hunk_num_lines(i) + 1
    hunks[i+2] = line_num
  end

  self._header, self._hunks = header, hunks
  self:render(lines)
end

---@param lines string[]
function PatchView:render(lines)
  vim.api.nvim_buf_set_option(self.popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(self.popup.bufnr, "readonly", false)

  vim.api.nvim_buf_set_lines(
    self.popup.bufnr, 0, -1, true, lines
  )

  vim.api.nvim_buf_set_option(self.popup.bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(self.popup.bufnr, "readonly", true)
end

function PatchView:mount()
  return self.popup:mount()
end

function PatchView:unmount()
  return self.popup:unmount()
end

-- keys handlers

---@return fun()
function PatchView:next_hunk_handler()
  return function()
    local cursor = vim.api.nvim_win_get_cursor(self.popup.winid)
    for i, hunk_start in ipairs(self._hunks) do
      if cursor[1] < hunk_start then
        local new_row = i < #self._hunks and hunk_start or hunk_start - 1
        vim.api.nvim_win_set_cursor(self.popup.winid, { new_row, cursor[2] })
        break
      end
    end
  end
end

---@return fun()
function PatchView:prev_hunk_handler()
  return function()
    local cursor = vim.api.nvim_win_get_cursor(self.popup.winid)
    for i, hunk_start in ipairs(self._hunks) do
      if cursor[1] <= hunk_start then
        local new_row = i > 1 and self._hunks[i-1] or 1
        vim.api.nvim_win_set_cursor(self.popup.winid, { new_row, cursor[2] })
        break
      end
    end
  end
end

---@return fun()
function PatchView:expand_handler()
  return function()
    local node = self.tree:get_node()
    if node and node:has_children() and not node:is_expanded() then
      node:expand()
      self.tree:render()
    else
      vim.cmd("normal! l")
    end
  end
end

---@return fun()
function PatchView:expand_collapse_handler()
  return function()
    local node = self.tree:get_node()
    if node and not node:has_children() then
      node = self.tree:get_node(node:get_parent_id() or 0)
    end

    if node then
      if node:is_expanded() then
        node:collapse()
      else
        node:expand()
      end
      self.tree:render()
    end
  end
end

---@return fun()
function PatchView:collapse_all_handler()
  return function()
    local updated = false

    for _, node in pairs(self.tree.nodes.by_id) do
      updated = node:collapse() or updated
    end

    if updated then
      self.tree:render()
    end
  end
end

---@return fun()
function PatchView:expand_all_handler()
  return function()
    local updated = false

    for _, node in pairs(self.tree.nodes.by_id) do
      updated = node:expand() or updated
    end

    if updated then
      self.tree:render()
    end
  end
end

return PatchView
