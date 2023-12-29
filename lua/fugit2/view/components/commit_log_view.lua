---Fugit2 Git commit graph/log sub view

local Object = require "nui.object"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"
local NuiLine = require "nui.line"
local string_utils = require "plenary.strings"

local utils = require "fugit2.utils"


local SYMBOLS = {
  CURRENT_COMMIT        = "●",
  COMMIT_BRANCH         = "│",
  COMMIT_BRANCH_JUMP    = "┆",
  COMMIT_EMPTY          = "",
  COMPLEX_MERGE_1       = "┬┆",
  COMPLEX_MERGE_2       = "╰┤",
  MERGE_COMMIT          = "󰍌 " ,
  --
  BRANCH_COMMIT_LEFT    = "┤",
  BRANCH_COMMIT_RIGHT   = "├",
  BRANCH_COMMIT_LRIGHT  = "┼",

  -- MERGE_UP_LEFT_RIGHT   = '┴',
  -- MERGE_UP_LEFT         = "╯",
  -- MERGE_UP_RIGHT        = '╰',
  -- MERGE_UP              = " ",
  MERGE_UP_DOWN         = "┼",
  MERGE_UP_DOWN_LEFT    = "├",
  MERGE_UP_DOWN_RIGHT   = "┤",
  MERGE_DOWN            = "┬",
  MERGE_DOWN_LEFT       = "╭",
  MERGE_DOWN_RIGHT      = "╮",
  MERGE_LEFT_RIGHT      = "─",
  MERGE_EMPTY           = " ",
  --
  BRANCH_UP             = "┴",
  BRANCH_UP_LEFT        = "╰",
  BRANCH_UP_RIGHT       = "╯",
  MISSING_PARENT        = "┆ ",
  MISSING_PARENT_BRANCH = "│ ",
  MISSING_PARENT_EMPTY  = "  ",
  -- Commit content
  MESSAGE_START         = "▊",
}

---Helper enum for graph column
---@enum Fugit2GitGraphColumn
local GitGraphColumn = {
  NONE   = 1, -- column not allocated
  COMMIT = 2, -- column contains main commit
  ACTIVE = 3, -- column is allocated by other branch
}

---@alias Fugit2GitGraphActiveBranch { j: integer, out_cols: integer[]? }
---@alias Fugit2GitGraphLine { cols: string[] }


---Helper class to store graph vis information
---@class Fugit2GitGraphCommitNodeVis
---@field j integer graph j coordinate
---@field start boolean? this commit start a branch
---@field active_cols integer[]? current active branch j
---@field out_cols integer[]? out branches column j
---@field merge_cols integer[]? merge branches column j


---@class Fugit2GitGraphCommitNode
---@field oid string commit oid
---@field message string commit message
---@field author string commit author
---@field parents string[]
---@field tags string[] Tags to show beside commit
---@field vis Fugit2GitGraphCommitNodeVis?
local GitGraphCommitNode = Object("Fugit2GitGraphCommitNode")


---Inits Fugit2GitGraphCommitNode
---@param oid string
---@param msg string
---@param parents Fugit2GitGraphCommitNode[]
function GitGraphCommitNode:init(oid, msg, author, parents, tags)
  self.oid = oid
  self.author = author
  self.message = msg
  self.parents = parents
  self.tags = tags
end


---@class Fugit2GitGraphCommitGraph
local GitGraphCommitGraph = Object("Fugit2GitGraphCommitGraph")


---@class Fugit2CommitLogView
---@field popup NuiPopup Commit popup.
---@field ns_id integer Namespace id.
---@field repo GitRepository
local CommitLogView = Object("Fugit2CommitLogView")


---Inits Fugit2GitGraph.
---@param ns_id integer
---@param title string
function CommitLogView:init(ns_id, title)
  self.ns_id = ns_id
  self.title = title

  -- popup
  self.popup = NuiPopup {
    ns_id = ns_id,
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      padding = {
        top = 0,
        bottom = 0,
        left = 1,
        right = 1,
      },
      text = {
        top = NuiText(title, "Fugit2FloatTitle"),
        top_align = "left",
      },
    },
    win_options = {
      winblend = 0,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = true,
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      buftype = "nofile",
      swapfile = false,
      syntax = "fugit2commitlog",
    },
  }

  -- sub components
  ---@type GitRevisionWalker?
  self._walker = nil
  ---@type NuiLine[]
  self._branch_lines, self._commit_lines = {}, {}
  ---@type Fugit2GitGraphCommitNode[]
  self._commits = {}
end


---@param mode string
---@param key string|string[]
---@param fn fun()|string
---@param opts table
function CommitLogView:map(mode, key, fn, opts)
  return self.popup:map(mode, key, fn, opts)
end


---@return integer Windid
function CommitLogView:winid()
  return self.popup.winid
end


---Updates buffer content with commit log
---@param commits Fugit2GitGraphCommitNode[]
function CommitLogView:update(commits)
  local width
  self._commits, width = self.prepare_commit_node_visualisation(commits)
  self._commit_lines = self.draw_commit_nodes(self._commits, width)
end


-- Prepares node visulasation information for each commit
---@param nodes Fugit2GitGraphCommitNode[] Commit Node in topo order.
---@return Fugit2GitGraphCommitNode[] out_nodes
---@return integer graph_width
function CommitLogView.prepare_commit_node_visualisation(nodes)
  ---@type {[string]: Fugit2GitGraphActiveBranch}
  local active_branches = {} -- mapping from oid to {j, out_cols? }
  ---@type Fugit2GitGraphActiveBranch?
  local branch -- track current active branch
  local col_arr = utils.BitArray.new() -- bitarray to save allocated columns

  -- travel nodes in sorted order
  for _, commit in ipairs(nodes) do
    commit.vis = { j = 1 }

    branch = active_branches[commit.oid]
    if branch then
      -- found entry in active_branches table
      active_branches[commit.oid] = nil -- delete old entry
    else
      -- append new col
      local unset = col_arr:set_k_unset_indices(1)
      branch = { j = unset[1] }
      commit.vis.start = true
    end

    commit.vis.j = branch.j

    -- get other active branches position
    local col_arr_copy = col_arr:copy()

    -- handle out branches
    if branch.out_cols then
      if branch.j > branch.out_cols[1] then
        -- swap branch.j with lowest out_cols
        local v = branch.j
        branch.j = table.remove(branch.out_cols, 1)
        commit.vis.j = branch.j
        utils.list_sorted_insert(branch.out_cols, v)
      end

      for _, col in ipairs(branch.out_cols) do
        col_arr:unset(col)
        col_arr_copy:unset(col)
      end

      commit.vis.out_cols = branch.out_cols
      branch.out_cols = nil -- delete out cols of active branches
      -- branch.main_merge = nil
    end

    local active_cols = col_arr_copy:unset(branch.j):get_set_indices()
    if #active_cols > 0 then
      commit.vis.active_cols = active_cols
    end

    -- prepare for next iter
    if #commit.parents > 0 then
      local parent_oid = commit.parents[1]
      local parent_branch = active_branches[parent_oid]

      if parent_branch then
        -- commit is a branch child, close this branch
        if parent_branch.out_cols then
          utils.list_sorted_insert(parent_branch.out_cols, branch.j)
        else
          parent_branch.out_cols = { branch.j }
        end
      else
        -- linear child
        active_branches[parent_oid] = branch
      end
    else -- no parent end branch
      col_arr:unset(branch.j)
    end

    if #commit.parents > 1 then
      -- merge commit
      -- first parent already allocated same j for merge commit
      -- branch.main_merge = true

      -- merge parent can be already be allocated
      local unallocated = {}
      local allocated_j = {}
      for _, p in ipairs(vim.list_slice(commit.parents, 2)) do
        local b = active_branches[p]
        if b then
          table.insert(allocated_j, b.j)
        else
          table.insert(unallocated, p)
        end
      end

      -- find free columns to allocate new branches
      local unset = col_arr:set_k_unset_indices(#unallocated)

      for k, col in ipairs(unset) do
        active_branches[unallocated[k]] = { j = col }
        utils.list_sorted_insert(allocated_j, col)
      end

      commit.vis.merge_cols = allocated_j
    end
  end

  return nodes, col_arr.n
end


---@param j integer
---@return string?
local function col_hl(j)
  if j >= 1 and j <=8 then
    return "Fugit2Branch" .. j
  end
end


---Draws graph line based on column of characters
---@param cols string[]
---@param width integer padding width, if == 0, no padding-right
---@param commit_j integer? commit column
---@return NuiLine
function CommitLogView.draw_graph_line(cols, width, commit_j)
  local graph_line = {}
  local space_pad, space_2_pad = "   ", "  "
  local dash_pad, dash_2_pad = "───", "──"
  local dash_empty = "────"
  local space_empty = NuiText("    ")
  local last_j

  local draw_dash = false

  local j = #cols
  if commit_j then
    j = commit_j
  end

  -- left to j
  last_j = 1
  for i = 1,j-1 do
    if cols[i] == "" then
      if draw_dash then
        table.insert(graph_line, NuiText(dash_empty, col_hl(last_j)))
      else
        table.insert(graph_line, space_empty)
      end
    elseif cols[i] == SYMBOLS.COMMIT_BRANCH or cols[i] == "|" then
      if draw_dash then
        table.insert(graph_line, NuiText(SYMBOLS.COMMIT_BRANCH_JUMP, col_hl(i)))
        table.insert(graph_line, NuiText(dash_pad, col_hl(last_j)))
      else
        table.insert(graph_line, NuiText(cols[i] .. space_pad, col_hl(i)))
      end
    else
      last_j = i
      local symbol = cols[i]
      if not draw_dash then
        if cols[i] == SYMBOLS.MERGE_DOWN then
          symbol = SYMBOLS.MERGE_DOWN_LEFT
        elseif cols[i] == SYMBOLS.MERGE_UP_DOWN then
          symbol = SYMBOLS.MERGE_UP_DOWN_LEFT
        elseif cols[i] == SYMBOLS.BRANCH_UP then
          symbol = SYMBOLS.BRANCH_UP_LEFT
        end
      end

      draw_dash = true
      table.insert(graph_line, NuiText(symbol .. dash_pad, col_hl(i)))
    end
  end

  -- commit symbol at j
  local k = #graph_line + 1
  graph_line[k] = NuiText(cols[j], col_hl(j))
  k = k + 1
  local is_wide_commit = string_utils.strdisplaywidth(cols[j]) > 1

  -- right to j
  last_j = #cols
  draw_dash = false
  for i = #cols,j+1,-1 do
    if is_wide_commit and i == j + 1 then
      dash_empty = dash_pad
      space_empty = NuiText(space_pad)
      dash_pad = dash_2_pad
      space_pad = space_2_pad
    end

    if cols[i] == "" then
      if draw_dash then
        table.insert(graph_line, k, NuiText(dash_empty, col_hl(last_j)))
      else
        table.insert(graph_line, k, space_empty)
      end
    elseif cols[i] == SYMBOLS.COMMIT_BRANCH or cols[i] == "|" then
      if draw_dash then
        table.insert(graph_line, k, NuiText(SYMBOLS.COMMIT_BRANCH_JUMP, col_hl(i)))
        table.insert(graph_line, k, NuiText(dash_pad, col_hl(last_j)))
      else
        table.insert(graph_line, k, NuiText(space_pad .. cols[i], col_hl(i)))
      end
    else
      last_j = i
      local symbol = cols[i]
      if not draw_dash then
        if cols[i] == SYMBOLS.MERGE_DOWN then
          symbol = SYMBOLS.MERGE_DOWN_RIGHT
        elseif cols[i] == SYMBOLS.MERGE_UP_DOWN then
          symbol = SYMBOLS.MERGE_UP_DOWN_RIGHT
        elseif cols[i] == SYMBOLS.BRANCH_UP then
          symbol = SYMBOLS.BRANCH_UP_RIGHT
        end
      end
      draw_dash = true
      table.insert(graph_line, k, NuiText(dash_pad .. symbol, col_hl(i)))
    end
  end

  -- padding right
  if width > #cols then
    local padding_right = NuiText(string.rep(" ", (width - #cols) * 4 - 1))
    table.insert(graph_line, padding_right)
  end

  return NuiLine(graph_line)
end

---@param vis Fugit2GitGraphCommitNodeVis
---@return NuiLine pre_line
local function draw_graph_node_pre_line_bare(vis)
  local max_pre_j = vis.j

  if vis.start then
    max_pre_j = 1
  end

  if vis.active_cols then
    max_pre_j = math.max(max_pre_j, vis.active_cols[#vis.active_cols])
  end

  if vis.out_cols then
    max_pre_j = math.max(max_pre_j, vis.out_cols[#vis.out_cols])
  end

  local pre_cols = utils.list_init(SYMBOLS.COMMIT_EMPTY, max_pre_j)
  utils.list_fill(pre_cols, SYMBOLS.COMMIT_BRANCH, vis.active_cols)
  utils.list_fill(pre_cols, SYMBOLS.COMMIT_BRANCH, vis.out_cols)

  if not vis.start then
    pre_cols[vis.j] = SYMBOLS.COMMIT_BRANCH
  end

  return CommitLogView.draw_graph_line(pre_cols, 0)
end


---@param vis Fugit2GitGraphCommitNodeVis
---@param width integer
---@return NuiLine commit_line
local function draw_graph_node_commit_line_bare(vis, width)
  local max_j = vis.j

  if vis.active_cols then
    max_j = math.max(max_j, vis.active_cols[#vis.active_cols])
  end

  local commit_cols = utils.list_init(SYMBOLS.COMMIT_EMPTY, max_j)
  utils.list_fill(commit_cols, SYMBOLS.COMMIT_BRANCH, vis.active_cols)

  commit_cols[vis.j] = SYMBOLS.CURRENT_COMMIT

  return CommitLogView.draw_graph_line(commit_cols, width, vis.j)
end

---@param vis Fugit2GitGraphCommitNodeVis
---@param width integer
---@return NuiLine commit_line
local function draw_graph_node_merge_line(vis, width)
  local max_j = vis.j

  if vis.active_cols then
    max_j = math.max(max_j, vis.active_cols[#vis.active_cols])
  end

  if vis.merge_cols then
    max_j = math.max(max_j, vis.merge_cols[#vis.merge_cols])
  end

  local commit_cols = utils.list_init(SYMBOLS.COMMIT_EMPTY, max_j)
  utils.list_fill(commit_cols, SYMBOLS.COMMIT_BRANCH, vis.active_cols)

  if vis.merge_cols then
    for _, i in ipairs(vis.merge_cols) do
      if commit_cols[i] ~= ""
        and not (vis.out_cols and vim.tbl_contains(vis.out_cols, i))
        then
        commit_cols[i] = SYMBOLS.MERGE_UP_DOWN
      else
        commit_cols[i] = SYMBOLS.MERGE_DOWN
      end
    end
  end

  commit_cols[vis.j] = SYMBOLS.MERGE_COMMIT

  return CommitLogView.draw_graph_line(commit_cols, width, vis.j)
end


---@param vis Fugit2GitGraphCommitNodeVis
---@param width integer
---@param commit_line_symbol boolean? use commit branch in preline
---@return NuiLine commit_line
local function draw_graph_node_branch_out_line(vis, width, commit_line_symbol)
  local max_j = vis.j

  if vis.active_cols then
    max_j = math.max(max_j, vis.active_cols[#vis.active_cols])
  end

  if vis.out_cols then
    max_j = math.max(max_j, vis.out_cols[#vis.out_cols])
  end

  local cols = utils.list_init("", max_j)
  utils.list_fill(cols, SYMBOLS.COMMIT_BRANCH, vis.active_cols)
  utils.list_fill(cols, SYMBOLS.BRANCH_UP, vis.out_cols)

  if commit_line_symbol and vis.out_cols then
    local min_out_j, max_out_j = vis.out_cols[1], vis.out_cols[#vis.out_cols]
    if min_out_j > vis.j then
      cols[vis.j] = SYMBOLS.BRANCH_COMMIT_RIGHT
    elseif max_out_j < vis.j then
      cols[vis.j] = SYMBOLS.BRANCH_COMMIT_LEFT
    else
      cols[vis.j] = SYMBOLS.BRANCH_COMMIT_LRIGHT
    end
  else
    cols[vis.j] = SYMBOLS.CURRENT_COMMIT
  end

  return CommitLogView.draw_graph_line(cols, width, vis.j)
end


---Draws commit graph similar to flog
---@param nodes Fugit2GitGraphCommitNode[]
---@param width integer graph part width
---@return NuiLine[] lines
function CommitLogView.draw_commit_nodes(nodes, width)
  local lines = {} -- output lines
  local pre_line, commit_line  = {}, {}
  width = width + 1

  for i, commit in ipairs(nodes) do
    if commit.vis then
      if commit.vis.out_cols and commit.vis.merge_cols then
        -- draw both merge and branch-out line
        pre_line = draw_graph_node_branch_out_line(commit.vis, 0, true)
        commit_line = draw_graph_node_merge_line(commit.vis, width)
      elseif commit.vis.out_cols then
        -- draw out_cols only
        pre_line = draw_graph_node_pre_line_bare(commit.vis)
        commit_line = draw_graph_node_branch_out_line(commit.vis, width, false)
      elseif commit.vis.merge_cols then
        -- draw merge_cols only
        pre_line = draw_graph_node_pre_line_bare(commit.vis)
        commit_line = draw_graph_node_merge_line(commit.vis, width)
      else
        -- draw commmit only
        pre_line = draw_graph_node_pre_line_bare(commit.vis)
        commit_line = draw_graph_node_commit_line_bare(commit.vis, width)
      end

      commit_line:append(SYMBOLS.MESSAGE_START .. " ", col_hl(commit.vis.j))
    end

    commit_line:append(utils.message_title_prettify(commit.message))

    -- add to lines
    if i ~= 1 then
      lines[#lines+1] = pre_line
    end
    lines[#lines+1] = commit_line
  end

  return lines
end


---Renders content for Fugit2GitGraph.
function CommitLogView:render()
  local bufnr = self.popup.bufnr
  local ns_id = self.ns_id

  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(bufnr, "readonly", false)

  local commit_lines = vim.tbl_map(
    function(line) return line:content() end,
    self._commit_lines
  )
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, commit_lines)

  for i, l in ipairs(self._commit_lines) do
    l:highlight(bufnr, ns_id, i)
  end

  vim.api.nvim_buf_set_option(bufnr, "readonly", true)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end


CommitLogView.CommitNode = GitGraphCommitNode


return CommitLogView
