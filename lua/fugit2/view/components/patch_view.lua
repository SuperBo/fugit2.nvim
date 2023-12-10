local NuiText = require "nui.text"
local NuiLine = require "nui.line"
local NuiTree = require "nui.tree"
local NuiPopup = require "nui.popup"
local Object = require "nui.object"


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
    },
  }

  -- sub components
  self.tree = nil
  self.header = {}


  -- keymaps
  self.popup:map("n", "]", self:next_hunk_handler(), { noremap = true, nowait = true })
  self.popup:map("n", "[", self:prev_hunk_handler(), { noremap = true, nowait = true })
end

local function tree_prepare_node(node)
  local line = NuiLine()

  -- line:append(string.rep("  ", node:get_depth() - 1))

  if node:has_children() then
    -- line:append(node:is_expanded() and " " or " ")
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

  line:append(node.text)

  return line
end

---Updates content with a given patch
---@param patch GitDiffPatchItem
function PatchView:update(patch)
  local nodes = {}

  local header = {}
  -- calculate hunk offsets
  local offsets = {}
  local start_idx = 5 -- first 4 lines are diff header

  for i = 0,patch.num_hunks-1 do
    offsets[i+1] = start_idx
    local num_lines = patch.patch:hunk_num_lines(i)
    start_idx = start_idx + num_lines + 1 -- 1 line for hunk signature
  end
  offsets[patch.num_hunks+1] = start_idx

  local patch_lines = vim.split(tostring(patch.patch), "\n", { plain=true })

  for i = 1,4 do
    header[i] = NuiLine { NuiText(patch_lines[i]) }
  end

  for i = 1,#offsets-1 do
    local start, stop = offsets[i], offsets[i+1]-1

    local children = {}
    for j = start+1,stop do
      if j == stop then
        table.insert(children, NuiTree.Node({
          text = patch_lines[j],
          id = j,
          hunk_id = i,
          last_line = true
        }))
      else
        table.insert(children, NuiTree.Node({
          text = patch_lines[j],
          id = j,
          hunk_id = i
        }))
      end
    end

    local hunk = NuiTree.Node({
      text = patch_lines[start],
      id = start,
      hunk_id = i
    }, children)
    hunk:expand()
    table.insert(nodes, hunk)
  end

  self.header = header
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
function PatchView:next_hunk_handler()
  return function()
    local node = self.tree:get_node()
    if node and node.hunk_id then
      -- TODO
    end
  end
end

function PatchView:prev_hunk_handler()
  return function()
    local node = self.tree:get_node()
    if node and node.hunk_id then
      -- TODO
    end
  end
end

return PatchView
