---Fugit2 Git status Unmerged/Staged/Unstaged list
---Mimic Vscode Source control view

local NuiSplit = require "nui.split"
local NuiTree = require "nui.tree"
local Object = require "nui.object"
local NuiLine = require "nui.line"
local WebDevIcons = require "nvim-web-devicons"
local strings = require "plenary.strings"
local plenary_filetype = require "plenary.filetype"

local git2 = require "fugit2.git2"
local utils = require "fugit2.utils"

-- ===================
-- | Status Sections |
-- ===================

local FILE_ENTRY_WIDTH = 40
local FILE_ENTRY_ALIGN = FILE_ENTRY_WIDTH - 1


local SOURCE_TREE_GIT_STATUS = {
  STAGED = 1,
  UNSTAGED = 2,
  CONFLICT = 3,
}


---@alias Fugit2SourceTreeItem { path: string, filename: string }

---@class Fugit2SourceTree
---@field ns_id integer
---@field pane NuiSplit
---@field tree NuiTree Conflict/Staged/Unstaged Tree
local SourceTree = Object "Fugit2SourceTree"

-- =================
-- | Tree funcions |
-- =================

-- Gets colors for a tree workdir node
---@param worktree_status GIT_DELTA
---@param modified boolean
---@return string text_color Text color
---@return string icon_color Icon color
local function tree_node_worktree_colors(worktree_status, modified)
  local text_color, icon_color = "", "Fugit2Unchanged"

  if worktree_status == git2.GIT_DELTA.CONFLICTED then
    text_color = "Fugit2Untracked"
    icon_color = "Fugit2Untracked"
  elseif worktree_status == git2.GIT_DELTA.UNTRACKED then
    text_color = "Fugit2Untracked"
    icon_color = "Fugit2Untracked"
  elseif worktree_status == git2.GIT_DELTA.IGNORED then
    text_color = "Fugit2Ignored"
    icon_color = "Fugit2Ignored"
  elseif worktree_status == git2.GIT_DELTA.MODIFIED then
    icon_color = "Fugit2Modified"
  end

  if modified then
    text_color = "Fugit2Modified"
  end

  return text_color, icon_color
end

-- Prepares node in tree.
---@param node NuiTree.Node
---@return NuiLine
local function status_tree_prepare_node(node)
  local line = NuiLine()
  line:append(string.rep("  ", node:get_depth() - 1))

  if node:has_children() then
    line:append(node:is_expanded() and " " or " ", node.color)
    line:append(node.text, node.color)
  else
    local left_align = node:get_depth() * 2
    local align = FILE_ENTRY_ALIGN
    local text = node.icon .. " " .. node.text
    local text_width = left_align + strings.strdisplaywidth(text)
    local text_color = node.color

    if text_width > FILE_ENTRY_WIDTH then
      align = math.ceil(text_width / FILE_ENTRY_WIDTH) * FILE_ENTRY_WIDTH - 1
    end

    align = (
      align
      - (node.modified and 3 or 0)
      - (node.insertions and node.insertions:len() + 1 or 0)
      - (node.deletions and node.deletions:len() + 1 or 0)
    )

    if node.modified then
      text_color = "Fugit2Modified"
    end

    line:append(
      strings.align_str(text, align - left_align),
      text_color
    )

    if node.modified then
      line:append("[+]", text_color)
    end

    if node.insertions then
      line:append("+" .. node.insertions, "Fugit2Insertions")
    end

    if node.deletions then
      line:append("-" .. node.deletions, "Fugit2Deletions")
    end

    line:append(" " .. node.status_icon, node.icon_color)

    -- line:append(node.modified and "[+] " or "    ", node.color)
    -- line:append(node.stage_icon .. " " .. node.wstatus .. node.istatus, node.stage_color)
  end

  return line
end

-- Setup create nodes in source tree
---@param merged GitStatusItem[]
---@param staged GitStatusItem[]
---@param unstaged GitStatusItem[]
---@return NuiTree.Node[] nodes List of nodes of tree
local function status_tree_construct_nodes(merged, staged, unstaged)
  local nodes = {}
  local node

  if #merged > 0 then
    node = NuiTree.Node({text = "  Merged changes", color = "Fugit2Untracked"}, merged)
    node:expand()
    nodes[#nodes+1] = node
  end

  if #staged > 0 then
    node = NuiTree.Node({text = "  Staged changes", color = "Fugit2Staged"}, staged)
    node:expand()
    nodes[#nodes+1] = node
  end

  if #unstaged > 0 then
    node = NuiTree.Node({text = "󰄷  Unstaged changes", color = "Fugit2Unstaged"}, unstaged)
    node:expand()
    nodes[#nodes+1] = node
  end

  return nodes
end


-- Gets colors for a tree index node
---@param index_status GIT_DELTA
---@param modified boolean
---@return string text_color Text color
---@return string icon_color Icon color
local function tree_node_index_colors(index_status, modified)
  local text_color, icon_color = "", "Fugit2Staged"

  if index_status == git2.GIT_DELTA.CONFLICTED then
    text_color = "Fugit2Untracked"
    icon_color = "Fugit2Untracked"
  end

  if modified then
    text_color = "Fugit2Modified"
  end

  return text_color, icon_color
end

-- Initializes Git SourceTree
---@param ns_id integer
function SourceTree:init(ns_id)
  self.ns_id = ns_id

  self.pane = NuiSplit {
    ns_id = ns_id,
    relative = "editor",
    position = "left",
    size = FILE_ENTRY_WIDTH,
    enter = false,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
    },
    win_options = {
      foldcolumn = "0",
      signcolumn = "no",
      number = false,
      cursorline = true,
    }
  }

  self.tree = NuiTree {
    bufnr = self.pane.bufnr,
    ns_id = ns_id,
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
---@param diff_head_to_index GitDiff?
function SourceTree:update(status, diff_head_to_index)
  local git_merged = {}
  local git_staged = {}
  local git_unstaged = {}

  -- get all bufs modified info
  local bufs = {}
  for _, bufnr in pairs(vim.tbl_filter(vim.api.nvim_buf_is_loaded, vim.api.nvim_list_bufs())) do
    local b = vim.bo[bufnr]
    if b then
      local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
      bufs[path] = {
        modified = b.modified,
        loaded = true,
      }
    end
  end

  -- get patch stats in diff_head_to_index
  local stats_head_to_index = {}
  if diff_head_to_index then
    local patches, _ = diff_head_to_index:patches(false)
    if patches then
      for _, p in ipairs(patches) do
        local stats, _ = p.patch:stats()
        if stats then
          stats_head_to_index[p.path] = stats
        end
      end
    end
  end

  for _, item in ipairs(status) do
    local filename = vim.fs.basename(item.path)
    local extension = plenary_filetype.detect(filename, { fs_access = false })
    local icon = WebDevIcons.get_icon(filename, extension, { default = true })
    local modified = bufs[item.path] and bufs[item.path].modified or false

    if item.worktree_status == git2.GIT_DELTA.CONFLICTED or item.index_status == git2.GIT_DELTA.CONFLICTED then
      -- merge/conflicst
      git_merged[#git_merged+1] = NuiTree.Node({
        id = "merged-" .. item.path,
        text = item.path,
        icon = icon,
        status_icon = utils.get_git_status_icon(git2.GIT_DELTA.CONFLICTED, ""),
        status = SOURCE_TREE_GIT_STATUS.CONFLICT,
        modified = modified
      })
    else
      if item.index_status ~= git2.GIT_DELTA.UNMODIFIED
        and item.index_status ~= git2.GIT_DELTA.UNTRACKED
      then
        -- staged
        local text_color, icon_color = tree_node_index_colors(item.worktree_status, modified)
        local stats = stats_head_to_index[item.path]
        local insertions, deletions
        if stats then
          insertions = stats.insertions > 0 and tostring(stats.insertions)
          deletions = stats.deletions > 0 and tostring(stats.deletions)
        end
        git_staged[#git_staged+1] = NuiTree.Node({
          id = "staged-" .. item.path,
          text = item.path,
          icon = icon,
          status_icon = utils.get_git_status_icon(item.index_status, ""),
          color = text_color,
          icon_color = icon_color,
          status = SOURCE_TREE_GIT_STATUS.STAGED,
          modified = modified,
          insertions = insertions,
          deletions = deletions,
        })
      end

      if item.worktree_status ~= git2.GIT_DELTA.UNMODIFIED then
        -- unstaged
        local text_color, icon_color = tree_node_worktree_colors(item.worktree_status, modified)
        git_unstaged[#git_unstaged+1] = NuiTree.Node({
          id = "unstaged-" .. item.path,
          text = item.path,
          icon = icon,
          status_icon = utils.get_git_status_icon(item.worktree_status, ""),
          color = text_color,
          icon_color = icon_color,
          status = SOURCE_TREE_GIT_STATUS.UNSTAGED,
          modified = modified
        })
      end
    end
  end

  self.tree:set_nodes(status_tree_construct_nodes(git_merged, git_staged, git_unstaged))
end


---@return NuiTree.Node?
---@param node_id string?
---@return integer? line_number
function SourceTree:get_node(node_id)
  local node, linenr = self.tree:get_node(node_id)
  if node and not node:has_children() then
    return node, linenr
  end
end

-- Renders status list/tree
function SourceTree:render()
  self.tree:render()
end

-- Mounts split pane
function SourceTree:mount()
  self.pane:mount()
end

-- Unmount split pane
function SourceTree:unmount()
  self.pane:unmount()
end

function SourceTree:focus()
  vim.api.nvim_set_current_win(self.pane.winid)
end

---@param buf_name string
function SourceTree:set_buf_name(buf_name)
  vim.api.nvim_buf_set_name(self.pane.bufnr, buf_name)
end

---@param mode string
---@param key string|string[]
---@param fn fun()|string
---@param opts table
function SourceTree:map(mode, key, fn, opts)
  return self.pane:map(mode, key, fn, opts)
end

---@param event string | string[]
---@param handler fun()
function SourceTree:on(event, handler)
  return self.pane:on(event, handler)
end

SourceTree.GIT_STATUS = SOURCE_TREE_GIT_STATUS

return SourceTree
