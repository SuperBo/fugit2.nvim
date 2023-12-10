local NuiText = require "nui.text"
local NuiLine = require "nui.line"
local NuiTree = require "nui.tree"
local NuiPopup = require "nui.popup"
local Object = require "nui.object"

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
  self.tree = nil
  self.header = {}

  -- keymaps
  local opts = { noremap = true, nowait = true }
  self.popup:map("n", "]", self:next_hunk_handler(), opts)
  self.popup:map("n", "[", self:prev_hunk_handler(), opts)
  local expand_collapse_handler = self:expand_collapse_handler()
  self.popup:map("n", "<cr>", expand_collapse_handler, opts)
  self.popup:map("n", "=", expand_collapse_handler, opts)
  self.popup:map("n", "l", self:expand_handler(), opts)
  self.popup:map("n", "H", self:collapse_all_handler(), opts)
  self.popup:map("n", "L", self:expand_all_handler(), opts)
end

local function tree_prepare_node(node)
  local line = NuiLine()
  local extmark

  if node:has_children() then
    -- line:append(node:is_expanded() and " " or " ")
    if not node:is_expanded() then
      extmark = "Visual"
    end
  elseif node.text:sub(1, 1) == " " then
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
---@param patch GitDiffPatchItem
function PatchView:update(patch)
  local patch_hunk = diff.parse_patch(tostring(patch.patch))

  self.header = vim.tbl_map(function(line)
    return NuiLine { NuiText(line) }
  end, patch_hunk.header)

  local nodes = vim.tbl_map(function(hunk)
    local children = vim.tbl_map(function(line)
      return NuiTree.Node({
        text = line.text,
        c    = line.c,
        id   = line.linenr
      })
    end, hunk.lines)
    children[#children].last_line = true

    local hunk_node = NuiTree.Node({
      text = hunk.header,
      id   = hunk.linenr
    }, children)
    hunk_node:expand()
    return hunk_node
  end, patch_hunk.hunks)

  self.tree = NuiTree {
    ns_id = self.ns_id,
    bufnr = self.popup.bufnr,
    nodes = nodes,
    prepare_node = tree_prepare_node,
  }
  self:render()
end

function PatchView:render()
  vim.api.nvim_buf_set_option(self.popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(self.popup.bufnr, "readonly", false)

  for i, line in ipairs(self.header) do
    line:render(self.popup.bufnr, self.ns_id, i)
  end

  if self.tree then
    self.tree:render(#self.header+1)
  end

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
    -- TODO
    local node = self.tree:get_node()
  end
end

---@return fun()
function PatchView:prev_hunk_handler()
  return function()
    -- TODO
    local node = self.tree:get_node()
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
