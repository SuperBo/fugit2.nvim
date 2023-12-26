---Fugit2 Git branches tree

local Object = require "nui.object"
local NuiTree = require "nui.tree"
local NuiLine = require "nui.line"

local utils = require "fugit2.utils"

-- ===============
-- | Branch Tree |
-- ===============


local BRANCH_ENTRY_PADDING = 49


---@class Fugit2GitBranchTree
---@field bufnr integer
---@field namespace integer
local GitBranchTree = Object("Fugit2GitBranchTree")


---@param node NuiTree.Node
local function branch_tree_prepare_node(node)
  local line = NuiLine()
  line:append(string.rep("  ", node:get_depth() - 1))

  if node:has_children() then
    local text = node:is_expanded() and "  " or "  "
    text = text .. node.text
    line:append(text, "Fugit2SymbolicRef")
  elseif node.is_active then
    local format_str = "%s %-" .. (BRANCH_ENTRY_PADDING - node:get_depth() * 2) .. "s%s"
    line:append(string.format(format_str, "󱓏", node.text, "󱕦"), "Fugit2BranchHead")
  else
    line:append("󰘬 " .. node.text)
  end

  return line
end


---@param bufnr integer
---@param namespace integer
function GitBranchTree:init(bufnr, namespace)
  self.bufnr = bufnr
  self.namespace = namespace

  self.tree = NuiTree {
    bufnr = bufnr,
    ns_id = namespace,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
    },
    prepare_node = branch_tree_prepare_node,
    nodes = {}
  }
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


return GitBranchTree
