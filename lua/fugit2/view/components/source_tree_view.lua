---Fugit2 Git status Unmerged/Staged/Unstaged list
---Mimic Vscode Source control view

local NuiSplit = require "nui.split"
local NuiTree = require "nui.tree"
local Object = require "nui.object"

local git2 = require "fugit2.git2"
local utils = require "fugit2.utils"

-- ===================
-- | Status Sections |
-- ===================

---@alias Fugit2SourceTreeItem { path: string, filename: string }

---@class Fugit2SourceTree
---@field ns_id integer
---@field pane NuiSplit
---@field tree NuiTree Conflict/Staged/Unstaged Tree
local SourceTree = Object "Fugit2SourceTree"

-- =================
-- | Tree funcions |
-- =================
local function status_tree_prepare_node() end

---@param merge GitStatusItem[]
---@param staged GitStatusItem[]
---@param unstaged GitStatusItem[]
---@param untracked GitStatusItem[]
local function status_tree_construct_nodes(merge, staged, unstaged, untracked) end

---@param ns_id integer
function SourceTree:init(ns_id)
  self.ns_id = ns_id

  self.pane = NuiSplit {
    ns_id = ns_id,
    relative = "editor",
    position = "left",
    size = 40,
    enter = false,
  }

  self.tree = NuiTree {
    bufnr = self.pane.bufnr,
    ns_id = ns_id,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
    },
    prepare_node = status_tree_prepare_node,
    nodes = {},
  }

  self._git = {}
  ---@type Fugit2SourceTreeItem[]
  self._git.staged = {}
  ---@type Fugit2SourceTreeItem[]
  self._git.unstaged = {}
  ---@type Fugit2SourceTreeItem[]
  self._git.merge = {}
end

---Update GitStatusList Pane
---@param status GitStatusItem[]
function SourceTree:update(status)
  -- get all bufs modified info
  local bufs = {}
  for _, bufnr in pairs(vim.tbl_filter(vim.api.nvim_buf_is_loaded, vim.api.nvim_list_bufs())) do
    local b = vim.bo[bufnr]
    if b and b.modified then
      local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
      bufs[path] = {
        modified = b.modified,
      }
    end
  end

  local git = self._git
  utils.list_clear(git.staged)
  utils.list_clear(git.unstaged)
  utils.list_clear(git.merge)

  for _, item in ipairs(status) do
    if item.worktree_status == git2.GIT_DELTA.CONFLICTED or item.index_status == git2.GIT_DELTA.CONFLICTED then
      -- merge/conflicst
      git.merge[#git.merge + 1] = {
        path = item.path,
        filename = vim.fs.basename(item.path),
      }
    else
      if item.index_status ~= git2.GIT_DELTA.UNMODIFIED then
        -- staged
        git.staged[#git.staged + 1] = {
          path = item.path,
          filename = vim.fs.basename(item.path),
        }
      end

      if item.worktree_status ~= git2.GIT_DELTA.UNMODIFIED then
        -- unstaged
        git.unstaged[#git.unstaged + 1] = {
          path = item.path,
          filename = vim.fs.basename(item.path),
        }
      end
    end
  end
end

---Renders status list/tree
function SourceTree:render()
  self.tree:render()
end

---Mounts split pane
function SourceTree:mount()
  self.pane:mount()
end

function SourceTree:focus()
  vim.api.nvim_set_current_win(self.pane.winid)
end

return SourceTree
