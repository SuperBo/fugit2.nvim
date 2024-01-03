---Fugit2 Git branches tree view

local NuiLine = require "nui.line"
local NuiText = require "nui.text"
local NuiPopup = require "nui.popup"
local NuiTree = require "nui.tree"
local Object = require "nui.object"

local utils = require "fugit2.utils"

-- ===============
-- | Branch Tree |
-- ===============


local BRANCH_ENTRY_PADDING = 49


---@class Fugit2GitBranchTree
---@field bufnr integer
---@field namespace integer
local GitBranchTree = Object("Fugit2GitBranchTree")


---@param ns_id integer
---@param width integer?
function GitBranchTree:init(ns_id, width)
  self.ns_id = ns_id
  self.width = width or BRANCH_ENTRY_PADDING

  self.popup = NuiPopup {
    ns_id = ns_id,
    enter = false,
    border = {
      style = "rounded",
      padding = { top = 0, bottom = 0, left = 1, right = 1 },
      text = {
        top = NuiText(" 󰳐 Branches ", "Fugit2FloatTitle"),
        top_align = "left",
        bottom = NuiText("[b]ranches", "FloatFooter"),
        bottom_align = "right",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = true,
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      swapfile = false,
      buftype  = "nofile",
    },
  }

  self.tree = NuiTree {
    bufnr = self.popup.bufnr,
    ns_id = ns_id,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
    },
    prepare_node = self._prepare_node(self.width - 6),
    nodes = {}
  }
end


---@param padding integer
---@return fun(node: NuiTree.Node): NuiLine
function GitBranchTree._prepare_node(padding)
  return function(node)
    local line = NuiLine()
    line:append(string.rep("  ", node:get_depth() - 1))

    if node:has_children() then
      local text = node:is_expanded() and "  " or "  "
      text = text .. node.text
      line:append(text, "Fugit2SymbolicRef")
    elseif node.is_active then
      local format_str = "%s %-" .. (padding - node:get_depth() * 2) .. "s%s"
      line:append(string.format(format_str, "󱓏", node.text, "󱕦"), "Fugit2BranchHead")
    else
      line:append("󰘬 " .. node.text)
    end

    return line
  end
end


function GitBranchTree:winid()
  return self.popup.winid
end

---@param mode string
---@param key string|string[]
---@param fn fun()|string
---@param opts table
function GitBranchTree:map(mode, key, fn, opts)
  return self.popup:map(mode, key, fn, opts)
end


---@param mode string
---@param key string|string[]
function GitBranchTree:unmap(mode, key)
  return self.popup:unmap(mode, key)
end


---@param event string | string[]
---@param handler fun()
function GitBranchTree:on(event, handler)
  return self.popup:on(event, handler)
end


---@param br GitBranch
---@return string
local function branch_path(br)
  return br.shorthand
end


---@param active_branch string?
---@return fun(br: GitBranch): NuiTree.Node
local function branch_node(active_branch)
  return function(br)
    local node = {
      id = br.name,
      type = br.type,
      text = vim.fs.basename(br.shorthand),
    }
    if active_branch and active_branch == br.name then
      node.is_active = true
    end
    return NuiTree.Node(node)
  end
end


---@param branches GitBranch[]
---@param active_branch string?
function GitBranchTree:update(branches, active_branch)
  local dir_tree = utils.build_dir_tree(branch_path, branches)
  local nodes = utils.build_nui_tree_nodes(branch_node(active_branch), dir_tree)
  self._active_branch = active_branch
  self.tree:set_nodes(nodes)
end


function GitBranchTree:render()
  self.tree:render()
end


---@return NuiTree.Node? node
---@return integer? linenr
function GitBranchTree:get_active_branch()
  if not self._active_branch then
    return nil, nil
  end

  local node, linenr = self.tree:get_node("-" .. self._active_branch)
  return node, linenr
end


---Scrolls to active branch
---@return integer?
function GitBranchTree:scroll_to_active_branch()
  local _, linenr = self:get_active_branch()
  local winid = self.popup.winid
  if linenr and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_set_cursor(winid, { linenr, 0 })
  end
  return linenr
end


---@return NuiTree.Node?
---@return integer? linenr
function GitBranchTree:get_child_node_linenr()
  local node, linenr, _ = self.tree:get_node() -- get current node

  -- depth first search to get first child
  while node and node:has_children() do
    local children = node:get_child_ids()
    node, linenr, _ = self.tree:get_node(children[1])
  end

  return node, linenr
end



return GitBranchTree
