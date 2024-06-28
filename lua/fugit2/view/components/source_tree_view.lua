---Fugit2 Git status Unmerged/Staged/Unstaged list
---Mimic Vscode Source control view

local NuiLine = require "nui.line"
local NuiSplit = require "nui.split"
local NuiTree = require "nui.tree"
local Object = require "nui.object"
local WebDevIcons = require "nvim-web-devicons"
local plenary_filetype = require "plenary.filetype"
local strings = require "plenary.strings"

local TreeBase = require "fugit2.view.components.base_tree_view"
local git2 = require "fugit2.git2"
local notifier = require "fugit2.notifier"
local utils = require "fugit2.utils"

-- ===================
-- | Status Sections |
-- ===================

local CONFLICTS_ID = "#CONFLICT"
local STAGED_ID = "#STAGED"
local UNSTAGED_ID = "#UNSTAGED"

local CONFLICTS_PREFIX = "merged-"
local STAGED_PREFIX = "staged-"
local UNSTAGED_PREFIX = "unstaged-"

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
---@return NuiLine?
local function status_tree_prepare_node(node)
  local line = NuiLine()
  line:append(string.rep("  ", node:get_depth() - 1))

  if node:has_children() then
    local children = node:get_child_ids()
    line:append(string.format("%s%s (%d)", node:is_expanded() and " " or " ", node.text, #children), node.color)
  elseif node.is_header then
    return nil
  else
    local left_align = node:get_depth() * 2
    local align = FILE_ENTRY_ALIGN
    local text = node.icon .. " " .. node.text
    local text_width = left_align + strings.strdisplaywidth(text)
    local text_color = node.color

    local insertions = node.insertions and string.format("+%d", node.insertions)
    local deletions = node.deletions and string.format("-%d", node.deletions)

    if text_width > FILE_ENTRY_WIDTH then
      align = math.ceil(text_width / FILE_ENTRY_WIDTH) * FILE_ENTRY_WIDTH - 1
    end

    align = (
      align
      - (node.modified and 3 or 0)
      - (insertions and insertions:len() or 0)
      - (deletions and deletions:len() or 0)
    )

    if node.modified then
      text_color = "Fugit2Modified"
    end

    line:append(strings.align_str(text, align - left_align), text_color)

    if node.modified then
      line:append("[+]", text_color)
    end

    if insertions then
      line:append(insertions, "Fugit2Insertions")
    end
    if deletions then
      line:append(deletions, "Fugit2Deletions")
    end

    local status_icon = " " .. utils.get_git_status_icon(node.git_status, "")
    line:append(status_icon, node.icon_color)

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
  local conflicts_header = NuiTree.Node({
    id = CONFLICTS_ID,
    text = " Merged changes",
    color = "Fugit2Untracked",
    is_header = true,
  }, merged)
  conflicts_header:expand()

  local staged_header = NuiTree.Node({
    id = STAGED_ID,
    text = " Staged changes",
    color = "Fugit2Staged",
    is_header = true,
  }, staged)
  staged_header:expand()

  local unstaged_header = NuiTree.Node({
    id = UNSTAGED_ID,
    text = "󰄷 Unstaged changes",
    color = "Fugit2Unstaged",
    is_header = true,
  }, unstaged)
  unstaged_header:expand()

  return { conflicts_header, staged_header, unstaged_header }
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
  self.namespace = ns_id

  self.pane = NuiSplit {
    ns_id = ns_id,
    relative = "editor",
    position = "left",
    size = FILE_ENTRY_WIDTH,
    enter = false,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
      filetype = "fugit2-source-tree",
    },
    win_options = {
      foldcolumn = "0",
      signcolumn = "no",
      number = false,
      cursorline = true,
    },
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
    local loaded = bufs[item.path]
    local modified = loaded and bufs[item.path].modified or false

    if item.worktree_status == git2.GIT_DELTA.CONFLICTED or item.index_status == git2.GIT_DELTA.CONFLICTED then
      -- merge/conflicst
      git_merged[#git_merged + 1] = NuiTree.Node {
        id = CONFLICTS_PREFIX .. item.path,
        text = item.path,
        icon = icon,
        status = SOURCE_TREE_GIT_STATUS.CONFLICT,
        git_status = git2.GIT_DELTA.CONFLICTED,
        modified = modified,
        loaded = loaded,
      }
    else
      if item.index_status ~= git2.GIT_DELTA.UNMODIFIED and item.index_status ~= git2.GIT_DELTA.UNTRACKED then
        -- staged
        local text_color, icon_color = tree_node_index_colors(item.index_status, modified)
        local stats = stats_head_to_index[item.path]
        local insertions, deletions
        if stats then
          insertions = stats.insertions
          deletions = stats.deletions
        end
        git_staged[#git_staged + 1] = NuiTree.Node {
          id = STAGED_PREFIX .. item.path,
          text = item.path,
          icon = icon,
          color = text_color,
          icon_color = icon_color,
          status = SOURCE_TREE_GIT_STATUS.STAGED,
          git_status = item.index_status,
          modified = modified,
          insertions = insertions,
          deletions = deletions,
          loaded = loaded,
        }
      end

      if item.worktree_status ~= git2.GIT_DELTA.UNMODIFIED then
        -- unstaged
        local text_color, icon_color = tree_node_worktree_colors(item.worktree_status, modified)
        git_unstaged[#git_unstaged + 1] = NuiTree.Node {
          id = UNSTAGED_PREFIX .. item.path,
          text = item.path,
          icon = icon,
          color = text_color,
          icon_color = icon_color,
          status = SOURCE_TREE_GIT_STATUS.UNSTAGED,
          git_status = item.worktree_status,
          modified = modified,
          loaded = loaded,
        }
      end
    end
  end

  self.tree:set_nodes(status_tree_construct_nodes(git_merged, git_staged, git_unstaged))
end

---@param node_id string?
---@return NuiTree.Node?
---@return integer? line_number
function SourceTree:get_node(node_id)
  local node, linenr = self.tree:get_node(node_id)
  if node and not node:has_children() then
    return node, linenr
  end
  return nil, nil
end

-- Gets node by git name
---@param git_path string
---@return NuiTree.Node? nuitree node
---@return integer? line_number
function SourceTree:get_node_by_git_path(git_path)
  local node, linenr
  for _, prefix in ipairs { CONFLICTS_PREFIX, STAGED_PREFIX, UNSTAGED_PREFIX } do
    local id = "-" .. prefix .. git_path
    node, linenr = self.tree:get_node(id)
    if node then
      return node, linenr
    end
  end
  return node, linenr
end

-- Adds, stage unstage or checkout a node from index.
---@param repo GitRepository
---@param index GitIndex
---@param action Fugit2IndexAction
---@param node NuiTree.Node
---@return boolean updated Tree is updated or not.
---@return boolean refresh Whether needed to do full refresh.
function SourceTree:index_add_reset_discard(repo, index, node, action)
  local err
  local updated = false
  local inplace = true -- whether can update status inplace

  local add = bit.band(action, TreeBase.IndexAction.ADD)
  local reset = bit.band(action, TreeBase.IndexAction.RESET)

  if add ~= 0 and node.status == SOURCE_TREE_GIT_STATUS.UNSTAGED then
    -- add to index if node is in unstaged section
    err = index:add_bypath(node.text)
    if err ~= 0 then
      notifier.error("Git error when adding to index", err)
      return false, false
    end

    updated = true
  elseif reset ~= 0 and node.status == SOURCE_TREE_GIT_STATUS.STAGED then
    -- remove from index
    err = repo:reset_default { node.text }
    if err == git2.GIT_ERROR.GIT_EUNBORNBRANCH then
      err = index:remove_bypath(node.text)
    end
    if err ~= 0 then
      notifier.error("Git error when unstage from index", err)
      return false, false
    end

    updated = true
  elseif action == TreeBase.IndexAction.DISCARD then
    --TODO
  end

  -- inplace update
  if updated and inplace then
    if self:update_single_node(repo, node) ~= 0 then
      -- require full refresh if inplace update failed
      inplace = false
    end
  end

  return updated, not inplace
end

-- Returns git path from a NuiTree.Node
---@param node NuiTree.Node
function SourceTree:_get_git_path(node)
  return node.text
end

-- Updates file node status info, usually called after stage/unstage
---@param repo GitRepository
---@param node NuiTree.Node
---@return GIT_ERROR
function SourceTree:update_single_node(repo, node)
  local git_path = self:_get_git_path(node)
  local worktree_status, index_status, err = repo:status_file(git_path)
  if err ~= 0 then
    return err
  end

  local tree = self.tree

  local wstatus_new = git2.status_char_dash(worktree_status)
  local istatus_new = git2.status_char_dash(index_status)

  -- delete node when status == "--" and not conflicted
  if wstatus_new == "-" and istatus_new == "-" then
    tree:remove_node(node:get_id())

    if node.status == SOURCE_TREE_GIT_STATUS.STAGED then
      tree:remove_node("-" .. STAGED_PREFIX .. git_path)
    elseif node.status == SOURCE_TREE_GIT_STATUS.UNSTAGED then
      tree:remove_node("-" .. UNSTAGED_PREFIX .. git_path)
    end

    return 0
  end

  if
    (node.status == SOURCE_TREE_GIT_STATUS.UNSTAGED and wstatus_new == "-")
    or (node.status == SOURCE_TREE_GIT_STATUS.STAGED and (istatus_new == "-" or istatus_new == "?"))
  then
    tree:remove_node(node:get_id())
  end

  -- Add node to staged section
  if index_status ~= git2.GIT_DELTA.UNMODIFIED and index_status ~= git2.GIT_DELTA.UNTRACKED then
    local new_id = STAGED_PREFIX .. git_path
    local staged_node = self.tree:get_node("-" .. new_id)

    if not staged_node then
      node.id = new_id
      node.status = SOURCE_TREE_GIT_STATUS.STAGED
      node.color, node.icon_color = tree_node_index_colors(index_status, node.modified)
      node.git_status = index_status

      tree:add_node(node, "-" .. STAGED_ID)
    else
      -- update staged_node
      staged_node.color, staged_node.icon_color = tree_node_index_colors(index_status, node.modified)
      staged_node.git_status = index_status

      local diff, _ = repo:diff_head_to_index(nil, { git_path })
      if diff then
        local stats = diff:stats()
        if stats and stats.changed == 1 then
          staged_node.insertions = stats.insertions
          staged_node.deletions = stats.deletions
        end
      end
    end
  end

  -- Add node to unstaged section
  if worktree_status ~= git2.GIT_DELTA.UNMODIFIED then
    local new_id = UNSTAGED_PREFIX .. git_path
    local unstaged_node = self.tree:get_node("-" .. new_id)

    if not unstaged_node then
      node.id = new_id
      node.status = SOURCE_TREE_GIT_STATUS.UNSTAGED
      node.color, node.icon_color = tree_node_worktree_colors(worktree_status, node.modified)
      node.git_status = worktree_status

      tree:add_node(node, "-" .. UNSTAGED_ID)
    end
  end

  return 0
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

---@param linenr integer line number
function SourceTree:set_cursor_line(linenr)
  vim.api.nvim_win_set_cursor(self.pane.winid, { linenr, 0 })
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
