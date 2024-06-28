---Fugit2 Git branches tree view

local NuiLine = require "nui.line"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"
local NuiTree = require "nui.tree"
local Object = require "nui.object"

local git2 = require "fugit2.git2"
local utils = require "fugit2.utils"

-- ===============
-- | Branch Tree |
-- ===============

local BRANCH_ENTRY_PADDING = 49

---@class Fugit2GitBranchMatch
---@field text string
---@field pos integer[]

---@class Fugit2GitBranchTree
---@field bufnr integer
---@field namespace integer
local GitBranchTree = Object "Fugit2GitBranchTree"

---@param ns_id integer
---@param width integer?
---@param enter boolean
function GitBranchTree:init(ns_id, width, enter)
  self.ns_id = ns_id
  self.width = width or BRANCH_ENTRY_PADDING

  self.popup = NuiPopup {
    ns_id = ns_id,
    enter = enter and true or false,
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
      buftype = "nofile",
    },
  }

  self.tree = NuiTree {
    bufnr = self.popup.bufnr,
    ns_id = ns_id,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
      filetype = "fugit2-ref-tree",
    },
    prepare_node = self._prepare_node(self.width - 6),
    nodes = {},
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
      local icon = utils.get_git_namespace_icon(git2.reference_name_namespace(node.id))
      line:append(icon)

      if not node.pos then
        line:append(node.text)
      else
        -- Render for matches
        local prev_j = 1
        local raw_text = node.text
        for _, j in ipairs(node.pos) do
          if j > prev_j then
            line:append(raw_text:sub(prev_j, j - 1))
          end
          line:append(raw_text:sub(j, j), "Fugit2Match")
          prev_j = j + 1
        end
        if prev_j <= raw_text:len() then
          line:append(raw_text:sub(prev_j))
        end
      end
    end

    return line
  end
end

function GitBranchTree:set_branch_title()
  local title = NuiText(" 󰳐 Branches ", "Fugit2FloatTitle")
  self.popup.border:set_text("top", title)
end

function GitBranchTree:set_tag_title()
  local title = NuiText("  Tags ", "Fugit2FloatTitle")
  self.popup.border:set_text("top", title)
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
function GitBranchTree:update_branches(branches, active_branch)
  local dir_tree = utils.build_dir_tree(branch_path, branches)
  local nodes = utils.build_nui_tree_nodes(branch_node(active_branch), dir_tree)
  self._active_branch = active_branch
  self.tree:set_nodes(nodes)
end

---@param branches table[]
function GitBranchTree:update_branches_match(branches)
  local nodes = {}
  for i, bm in ipairs(branches) do
    nodes[i] = NuiTree.Node {
      id = bm.branch.name,
      type = bm.branch.type,
      text = bm.branch.shorthand,
      pos = bm.pos,
    }
  end
  self._active_branch = nil
  self.tree:set_nodes(nodes)
end

---@param tags string[]
function GitBranchTree:update_tags(tags)
  local nodes = {}
  for i, t in ipairs(tags) do
    nodes[i] = NuiTree.Node { id = "refs/tags/" .. t, text = t }
  end
  self._active_branch = nil
  self.tree:set_nodes(nodes)
end

---@param tags Fugit2GitBranchMatch
function GitBranchTree:update_tags_match(tags)
  local nodes = {}
  for i, tm in ipairs(tags) do
    nodes[i] = NuiTree.Node {
      id = "refs/tags/" .. tm.text,
      text = tm.text,
      pos = tm.pos,
    }
  end
  self._active_branch = nil
  self.tree:set_nodes(nodes)
end

function GitBranchTree:render()
  self.tree:render(1)
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

function GitBranchTree:set_cursor(linenr, col)
  if vim.api.nvim_win_is_valid(self.popup.winid) then
    local line_count = vim.api.nvim_buf_line_count(self.popup.bufnr)
    local new_line = math.min(math.max(linenr, 1), line_count)
    vim.api.nvim_win_set_cursor(self.popup.winid, { new_line, col })
  end
end

function GitBranchTree:get_cursor()
  return vim.api.nvim_win_get_cursor(self.popup.winid)
end

return GitBranchTree
