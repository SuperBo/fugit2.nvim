---Base class for GitStatusView and GitDiffView

local Object = require "nui.object"
local iterators = require "plenary.iterators"

local utils = require "fugit2.utils"

---@class Fugit2GitStatusDiffBase
local GitStatusDiffBase = Object "Fugit2GitStatusDiffBase"

-- Inits GitStatusDiffBase object
---@param ns_id integer
---@param repo GitRepository
---@param index GitIndex?
function GitStatusDiffBase:init(ns_id, repo, index)
  self.ns_id = ns_id
  self.repo = repo

  if index then
    self.index = index
  else
    local _index, err = repo:index()
    if not _index then
      error("[Fugit2] Can't read index from repo, " .. err)
    end
    self.index = _index
  end

  self._git = {
    path = repo:workdir(),
    index_updated = false,
    index_inmemory = self.index:in_memory(),
  }
end

function GitStatusDiffBase:update() end

function GitStatusDiffBase:render() end

---@param node NuiTree.Node
function GitStatusDiffBase:_remove_cached_states(node) end

function GitStatusDiffBase:_refresh_views() end

---@param tree NuiTree
---@param node NuiTree.Node?
---@return NuiTree.Node[]
local function get_leaves(tree, node)
  local parent_id = node and node:get_id() or nil
  local nodes = {}
  local children = tree:get_nodes(parent_id)
  for _, child in ipairs(children) do
    if not child:has_children() then
      nodes[#nodes + 1] = child
    else
      local sub_nodes = get_leaves(tree, child)
      vim.list_extend(nodes, sub_nodes)
    end
  end

  return nodes
end

---@param action Fugit2IndexAction
function GitStatusDiffBase:_index_add_reset_discard_all(action)
  local tree = self._views.files
  local bufnr = vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local nodes

  nodes = iterators.range(1, line_count, 1):map(function(linenr)
    return tree.tree:get_node(linenr)
  end)

  nodes = nodes:filter(function(node)
    return not node:has_children()
  end)

  self:_stage_change_post(iterators.iter(nodes), action)
end

---@param action Fugit2IndexAction
function GitStatusDiffBase:_index_add_reset_discard(action)
  local tree = self._views.files
  local nodes

  local node, _ = tree.tree:get_node()
  if node == nil then
    return
  end

  if not node:has_children() then
    nodes = iterators.iter { node }
  else
    node:expand()
    nodes = iterators.iter(get_leaves(tree.tree, node))
  end

  self:_stage_change_post(nodes, action)
end

---@param action Fugit2IndexAction
function GitStatusDiffBase:_index_add_reset_discard_visual(action)
  local tree = self._views.files
  local nodes

  local cursor_start = vim.fn.getpos("v")[2]
  local cursor_end = vim.fn.getpos(".")[2]
  if cursor_end < cursor_start then
    cursor_start, cursor_end = cursor_end, cursor_start
  end

  nodes = iterators.range(cursor_start, cursor_end, 1):map(function(linenr)
    return tree.tree:get_node(linenr)
  end)

  nodes = nodes:filter(function(node)
    return not node:has_children()
  end)

  vim.api.nvim_feedkeys(utils.KEY_ESC, "n", false)

  self:_stage_change_post(nodes, action)
end

---@param action Fugit2IndexAction
function GitStatusDiffBase:_stage_change_post(nodes, action)
  local git = self._git
  local tree = self._views.files

  local results = nodes
    :map(function(node)
      local is_updated, is_refresh = tree:index_add_reset_discard(self.repo, self.index, node, action)
      if is_updated then
        -- remove cached diff
        self:_remove_cached_states(node)
      end

      return { is_updated, is_refresh }
    end)
    :tolist()

  local updated = utils.list_any(function(r)
    return r[1]
  end, results)
  local refresh = utils.list_any(function(r)
    return r[2]
  end, results)

  if not updated then
    return
  end

  if refresh then
    self:update()
    self:render()
  else
    tree:render()
  end

  git.index_updated = true

  -- refresh other views
  self:_refresh_views()
end

return GitStatusDiffBase
