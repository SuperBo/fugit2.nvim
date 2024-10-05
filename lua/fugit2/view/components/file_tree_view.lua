---Fugit2 Git status file tree

local NuiLine = require "nui.line"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"
local NuiTree = require "nui.tree"
local Object = require "nui.object"
local Path = require "plenary.path"
local WebDevIcons = require "nvim-web-devicons"
local plenary_filetype = require "plenary.filetype"
local strings = require "plenary.strings"

local TreeBase = require "fugit2.view.components.base_tree_view"
local git2 = require "fugit2.git2"
local notifier = require "fugit2.notifier"
local utils = require "fugit2.utils"

-- =================
-- |  Status tree  |
-- =================

---@class Fugit2StatusTreeNodeData
---@field id string
---@field text string
---@field icon string
---@field color string Extmark.
---@field wstatus string Worktree short status.
---@field istatus string Index short status.
---@field modified boolean Buffer is modifed or not
---@field loaded boolean Buffer is loaded or not

-- Gets colors for a tree node
---@param worktree_status GIT_DELTA
---@param index_status GIT_DELTA
---@param modified boolean
---@return string text_color Text color
---@return string icon_color Icon color
---@return string status_icon Status icon
local function tree_node_colors(worktree_status, index_status, modified)
  local text_color, icon_color = "Fugit2Modifier", "Fugit2Modifier"
  local status_icon = utils.get_git_status_icon(worktree_status, "  ")

  if worktree_status == git2.GIT_DELTA.CONFLICTED then
    text_color = "Fugit2Untracked"
    icon_color = "Fugit2Untracked"
  elseif worktree_status == git2.GIT_DELTA.UNTRACKED then
    text_color = "Fugit2Untracked"
    icon_color = "Fugit2Untracked"
  elseif worktree_status == git2.GIT_DELTA.IGNORED or index_status == git2.GIT_DELTA.IGNORED then
    text_color = "Fugit2Ignored"
    icon_color = "Fugit2Ignored"
    status_icon = utils.get_git_status_icon(git2.GIT_DELTA.IGNORED, "  ")
  elseif index_status == git2.GIT_DELTA.UNMODIFIED then
    text_color = "Fugit2Unchanged"
    icon_color = "Fugit2Unstaged"
    status_icon = "󰆢 "
  elseif worktree_status == git2.GIT_DELTA.MODIFIED then
    text_color = "Fugit2Modified"
    icon_color = "Fugit2Staged"
  else
    text_color = "Fugit2Staged"
    icon_color = "Fugit2Staged"
    status_icon = utils.get_git_status_icon(index_status, "󰱒 ")
  end

  if modified then
    text_color = "Fugit2Modified"
  end

  return text_color, icon_color, status_icon
end

---@param item GitStatusItem
---@param bufs table
---@param stats_head_to_index { [string]: GitDiffStats }
---@return NuiTree.Node
local function tree_node_data_from_item(item, bufs, stats_head_to_index)
  local path = item.path
  local alt_path
  if item.renamed and item.worktree_status == git2.GIT_DELTA.UNMODIFIED then
    path = item.new_path or ""
  end

  local filename = vim.fs.basename(path)
  local extension = plenary_filetype.detect(filename, { fs_access = false })
  local loaded = bufs[path] ~= nil
  local modified = loaded and bufs[path].modified or false
  local conflicted = (
    item.worktree_status == git2.GIT_DELTA.CONFLICTED or item.index_status == git2.GIT_DELTA.CONFLICTED
  )

  local icon = WebDevIcons.get_icon(filename, extension, { default = true })
  local wstatus = git2.status_char_dash(item.worktree_status)
  local istatus = git2.status_char_dash(item.index_status)

  local text_color, icon_color, stage_icon = tree_node_colors(item.worktree_status, item.index_status, modified)

  local insertions, deletions
  if item.index_status ~= git2.GIT_DELTA.UNMODIFIED and item.index_status ~= git2.GIT_DELTA.UNTRACKED then
    local stats = stats_head_to_index[item.path]
    if stats then
      insertions = stats.insertions
      deletions = stats.deletions
    end
  end

  local rename = ""
  if item.renamed and item.index_status == git2.GIT_DELTA.UNMODIFIED then
    rename = " -> " .. utils.make_relative_path(vim.fs.dirname(item.path), item.new_path)
    alt_path = item.new_path
  elseif item.renamed and item.worktree_status == git2.GIT_DELTA.UNMODIFIED then
    rename = " <- " .. utils.make_relative_path(vim.fs.dirname(item.new_path), item.path)
    alt_path = item.path
  end

  local text = filename .. rename

  return NuiTree.Node {
    id = path,
    alt_path = alt_path,
    text = text,
    icon = icon,
    color = text_color,
    wstatus = wstatus,
    istatus = istatus,
    stage_icon = stage_icon,
    stage_color = icon_color,
    conflicted = conflicted,
    modified = modified,
    loaded = loaded,
    insertions = insertions,
    deletions = deletions,
  }
end

---@class Fugit2GitStatusTreeState
---@field padding integer

---@param states Fugit2GitStatusTreeState file entry padding
---@return fun(node: NuiTree.Node): NuiLine
local function create_tree_prepare_node_fn(states)
  return function(node)
    local line = NuiLine()
    line:append(string.rep("  ", node:get_depth() - 1))

    if node:has_children() then
      line:append(node:is_expanded() and "  " or "  ", "Fugit2SymbolicRef")
      line:append(node.text, "Fugit2SymbolicRef")
      if not node:is_expanded() then
        line:append(" (" .. tostring(node.num_leaves) .. ")", "Fugit2ObjectId")
      end
    else
      local insertions = node.insertions and string.format(" +%d", node.insertions)
      local deletions = node.deletions and string.format(" -%d", node.deletions)

      local left_align = (
        states.padding
        - node:get_depth() * 2
        - (node.modified and 4 or 0)
        - (insertions and insertions:len() or 0)
        - (deletions and deletions:len() or 0)
      )
      line:append(strings.align_str(node.icon .. " " .. node.text, left_align), node.color)

      if node.modified then
        line:append(" [+]", node.color)
      end

      if insertions then
        line:append(insertions, "Fugit2Insertions")
      end
      if deletions then
        line:append(deletions, "Fugit2Deletions")
      end

      line:append(" " .. node.stage_icon .. " " .. node.wstatus .. node.istatus, node.stage_color)
    end

    return line
  end
end

---@class Fugit2GitStatusTree
---@field ns_id integer
---@field tree NuiTree
---@field popup NuiPopup
local GitStatusTree = Object "Fugit2GitStatusTree"

---@param ns_id integer
---@param top_title string
---@param bottom_title string
---@param min_width integer
function GitStatusTree:init(ns_id, top_title, bottom_title, min_width)
  self.namespace = ns_id

  self.popup = NuiPopup {
    ns_id = ns_id,
    enter = false,
    focusable = true,
    zindex = 50,
    border = {
      style = "rounded",
      padding = { left = 1, right = 1 },
      text = {
        top = NuiText(top_title, "Fugit2FloatTitle"),
        top_align = "left",
        bottom = NuiText(bottom_title, "FloatFooter"),
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
      buftype = "nofile",
      filetype = "fugit2-file-tree",
    },
  }

  ---@type Fugit2GitStatusTreeState
  self.states = { padding = min_width - 10 }

  self.tree = NuiTree {
    bufnr = self.popup.bufnr,
    ns_id = ns_id,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
    },
    prepare_node = create_tree_prepare_node_fn(self.states),
    nodes = {},
  }
end

---@return NuiTree.Node?
---@return integer? linenr
function GitStatusTree:get_child_node_linenr()
  local node, linenr, _ = self.tree:get_node() -- get current node

  -- depth first search to get first child
  while node and node:has_children() do
    local children = node:get_child_ids()
    node, linenr, _ = self.tree:get_node(children[1])
  end

  return node, linenr
end

---@param status GitStatusItem[]
---@param git_path string git root path, used to detect modifed buffer
---@param diff_head_to_index GitDiff? diff head to index
function GitStatusTree:update(status, git_path, diff_head_to_index)
  -- get all bufs modified info
  local bufs = {}
  for _, bufnr in pairs(vim.tbl_filter(vim.api.nvim_buf_is_loaded, vim.api.nvim_list_bufs())) do
    local b = vim.bo[bufnr]
    if b then
      local path = Path:new(vim.api.nvim_buf_get_name(bufnr)):make_relative(git_path)
      bufs[path] = {
        modified = b.modified,
      }
    end
  end

  -- get stats head to index
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

  -- prepare tree
  local dir_tree = utils.build_dir_tree(function(sts)
    if sts.renamed and sts.worktree_status == git2.GIT_DELTA.UNMODIFIED then
      return sts.new_path
    end
    return sts.path
  end, status)

  dir_tree = utils.compress_dir_tree(dir_tree)

  local nodes, _ = utils.build_nui_tree_nodes(function(item)
    return tree_node_data_from_item(item, bufs, stats_head_to_index)
  end, dir_tree)
  self.tree:set_nodes(nodes)
end

-- Returns git path from a NuiTree.Node
---@param node NuiTree.Node
function GitStatusTree:_get_git_path(node)
  return node.id
end

-- Adds, stage unstage or checkout a node from index.
---@param repo GitRepository
---@param index GitIndex
---@param action Fugit2IndexAction
---@param node NuiTree.Node
---@return boolean updated Tree is updated or not.
---@return boolean refresh Whether needed to do full refresh.
function GitStatusTree:index_add_reset_discard(repo, index, node, action)
  local err
  local updated = false
  local inplace = true -- whether can update status inplace

  local add = bit.band(action, TreeBase.IndexAction.ADD)
  local reset = bit.band(action, TreeBase.IndexAction.RESET)

  if add ~= 0 and node.alt_path and (node.wstatus == "R" or node.wstatus == "M") then
    -- rename
    err = index:add_bypath(node.alt_path)
    if err ~= 0 then
      notifier.error("Git error when handling rename", err)
      return false, false
    end

    err = index:remove_bypath(node.id)
    if err ~= 0 then
      notifier.error("Git error when handling rename", err)
      return false, false
    end

    updated = true
    inplace = false -- requires full refresh
  elseif add ~= 0 and (node.wstatus == "?" or node.wstatus == "T" or node.wstatus == "M" or node.conflicted) then
    -- add to index if worktree status is in (UNTRACKED, MODIFIED, TYPECHANGE)
    err = index:add_bypath(node.id)
    if err ~= 0 then
      notifier.error("Git error when adding to index", err)
      return false, false
    end

    updated = true
  elseif add ~= 0 and node.wstatus == "D" then
    -- remove from index
    err = index:remove_bypath(node.id)
    if err ~= 0 then
      notifier.error("Git error when removing from index", err)
      return false, false
    end

    updated = true
  elseif reset ~= 0 and node.alt_path and (node.istatus == "R" or node.istatus == "M") then
    -- reset both paths if rename in index
    err = repo:reset_default { node.id, node.alt_path }
    if err ~= 0 then
      notifier.error("Git error when reset rename", err)
      return false, false
    end

    updated = true
    inplace = false -- requires full refresh
  elseif reset ~= 0 and node.istatus ~= "-" and node.istatus ~= "?" then
    -- else reset if index status is not in (UNCHANGED, UNTRACKED, RENAMED)
    err = repo:reset_default { node.id }
    if err == git2.GIT_ERROR.GIT_EUNBORNBRANCH then
      err = index:remove_bypath(node.id)
    end
    if err ~= 0 then
      notifier.error("Git error when unstage from index", err)
      return false, false
    end

    updated = true
  elseif action == TreeBase.IndexAction.DISCARD and node.wstatus ~= "-" then
    err = repo:checkout_index(index, git2.GIT_CHECKOUT.FORCE, { node.id })
    if err ~= 0 then
      notifier.error("Git error when checkout from head", err)
      return false, false
    end

    updated = true

    if node.loaded then
      vim.cmd.checktime(self:_get_git_path(node))
    end
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

---Updates file node status info, usually called after stage/unstage
---@param repo GitRepository
---@param node NuiTree.Node
---@return GIT_ERROR
function GitStatusTree:update_single_node(repo, node)
  if not node.id then
    return 0
  end

  local worktree_status, index_status, err = repo:status_file(node.id)
  if err ~= 0 then
    return err
  end

  node.wstatus = git2.status_char_dash(worktree_status)
  node.istatus = git2.status_char_dash(index_status)
  node.color, node.stage_color, node.stage_icon =
    tree_node_colors(worktree_status, index_status, node.modified or false)
  node.conflicted = worktree_status == git2.GIT_DELTA.CONFLICTED or index_status == git2.GIT_DELTA.CONFLICTED

  -- update insertions and deletions
  if node.istatus ~= "-" and node.istatus ~= "?" then
    local diff, _ = repo:diff_head_to_index(nil, { node.id })
    if diff then
      local stats = diff:stats()
      if stats and stats.changed == 1 then
        node.insertions = stats.insertions
        node.deletions = stats.deletions
      end
    end
  else
    node.insertions = nil
    node.deletions = nil
  end

  -- delete node when status == "--" and not conflicted
  if node.wstatus == "-" and node.istatus == "-" and not node.conflicted then
    local parent_id = node:get_parent_id()
    self.tree:remove_node(node:get_id())
    while parent_id ~= nil do
      local n = self.tree:get_node(parent_id)
      if n and not n:has_children() then
        parent_id = n:get_parent_id()
        self.tree:remove_node(n:get_id())
      else
        break
      end
    end
  end

  return 0
end

---@param width integer
function GitStatusTree:set_width(width)
  self.states.padding = width - 10
end

function GitStatusTree:render()
  vim.api.nvim_buf_set_option(self.popup.bufnr, "readonly", false)
  self.tree:render()
  vim.api.nvim_buf_set_option(self.popup.bufnr, "readonly", true)
end

function GitStatusTree:focus()
  local winid = self.popup.winid
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_current_win(winid)
  end
end

---@param mode string
---@param key string|string[]
---@param fn fun()|string
---@param opts table
function GitStatusTree:map(mode, key, fn, opts)
  return self.popup:map(mode, key, fn, opts)
end

---@param event string | string[]
---@param handler fun()
function GitStatusTree:on(event, handler)
  return self.popup:on(event, handler)
end

return GitStatusTree
