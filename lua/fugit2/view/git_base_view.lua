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
    path = vim.fn.fnamemodify(repo:repo_path(), ":p:h:h"),
    index_updated = false,
  }
end

function GitStatusDiffBase:update() end

function GitStatusDiffBase:render() end

---@param node NuiTree.Node
function GitStatusDiffBase:_remove_cached_states(node) end

function GitStatusDiffBase:_refresh_views() end

---@param is_visual_mode boolean
---@param action Fugit2IndexAction
function GitStatusDiffBase:_index_add_reset_discard(is_visual_mode, action)
  local tree = self._views.files
  local git = self._git
  local nodes

  if not is_visual_mode then
    local node, _ = tree.tree:get_node()
    nodes = iterators.iter { node }
  else
    local cursor_start = vim.fn.getpos("v")[2]
    local cursor_end = vim.fn.getpos(".")[2]
    if cursor_end < cursor_start then
      cursor_start, cursor_end = cursor_end, cursor_start
    end

    nodes = iterators.range(cursor_start, cursor_end, 1):map(function(linenr)
      return tree.tree:get_node(linenr)
    end)

    vim.api.nvim_feedkeys(utils.KEY_ESC, "n", false)
  end

  nodes = nodes:filter(function(node)
    return not node:has_children()
  end)

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

-- Add/reset/discard file entries handler.
---@param is_visual boolean whether this handler is called in visual mode.
---@param action Fugit2IndexAction index action
---@return function
function GitStatusDiffBase:_index_add_reset_handler(is_visual, action)
  return function()
    self:_index_add_reset_discard(is_visual, action)
  end
end

return GitStatusDiffBase
