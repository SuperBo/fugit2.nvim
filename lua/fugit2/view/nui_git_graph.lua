-- NUI Git graph module


local NuiLine = require "nui.line"
local NuiText = require "nui.text"
local Object = require "nui.object"
local event = require "nui.utils.autocmd".event

local git2 = require "fugit2.git2"
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

  MERGE_UP_LEFT_RIGHT   = '┴',
  MERGE_UP_LEFT         = "╯",
  MERGE_UP_RIGHT        = '╰',
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
}

---@class ActiveBranchItem
---@field j integer
---@field out_cols integer[]? optional out_cols


-- Helper class to store graph vis information
---@class NuiGitGraphCommitNodeVis
---@field j integer graph j coordinate
---@field start boolean? this commit start a branch
---@field active_cols integer[]? current active branch j
---@field out_cols integer[]? out branches column j
---@field merge_cols integer[]? merge branches column j


-- Helper enum for graph column
---@enum NuiGitGraphColumn
local GitGraphColumn = {
  NONE   = 1, -- column not allocated
  COMMIT = 2, -- column contains main commit
  ACTIVE = 3, -- column is allocated by other branch
}

---@class NuiGitGraphLine
---@field cols string[]


---@class NuiGitGraphCommitNode
---@field oid string
---@field message string
---@field parents string[]
---@field vis NuiGitGraphCommitNodeVis?
local NuiGitGraphCommitNode = Object "NuiGitGraphCommitNode"


-- Inits NuiGitGraphCommitNode
---@param oid string
---@param msg string
---@param parents NuiGitGraphCommitNode[]
function NuiGitGraphCommitNode:init(oid, msg, parents)
  self.oid = oid
  self.message = msg
  self.parents = parents
end


---@class NuiGitGraphCommitGraph
local NuiGitGraphCommitGraph = Object("NuiGitGraphCommitGraph")


---@class NuiGitGraph
---@field branch_bufnr integer Branch popup buf number.
---@field commit_bufnr integer Commit popup buf number.
---@field ns_id integer Namespace id.
---@field repo GitRepository
local NuiGitGraph = Object("NuiGitGraph")


-- Inits NuiGitGraph.
---@param branch_bufnr integer
---@param commit_bufnr integer
---@param ns_id integer
---@param repo GitRepository
function NuiGitGraph:init(branch_bufnr, commit_bufnr, ns_id, repo)
  if not vim.api.nvim_buf_is_valid(branch_bufnr) then
    error("invalid bufnr " .. branch_bufnr)
  end

  if not vim.api.nvim_buf_is_valid(commit_bufnr) then
    error("invalid bufnr " .. commit_bufnr)
  end

  self.branch_bufnr = branch_bufnr
  self.commit_bufnr = commit_bufnr

  self.ns_id = -1
  if ns_id then
    self.ns_id = ns_id
  end

  if not repo then
    error("Null repo ")
  end

  self.repo = repo

  ---@type GitRevisionWalker?
  self._walker = nil
  ---@type NuiLine[]
  self._branch_lines, self._commit_lines = {}, {}
  ---@type GitBranch[]
  self._branches = {}
  ---@type NuiGitGraphCommitNode[]
  self._commits = {}

  self:update()
end


-- Updates git branch and commits.
function NuiGitGraph:update()
  for i=#self._branch_lines,1,-1 do
    self._branch_lines[i] = nil
  end
  for i=#self._commit_lines,1,-1 do
    self._commit_lines[i] = nil
  end

  -- Gets all branches
  local branches, err
  branches, err = self.repo:branches(true, false)
  if not branches then
    self._branches = {}
    self._branch_lines = {
      NuiLine { NuiText(string.format("Git2 Error code: %d", err), "Error") }
    }
  else
    local branch_icon = utils.get_git_namespace_icon(git2.GIT_REFERENCE_NAMESPACE.BRANCH)
    self._branches = branches
    for i, branch in ipairs(branches) do
      self._branch_lines[i] = NuiLine { NuiText( branch_icon .. branch.shorthand) }
    end
  end

  -- Gets commits
  local walker = self._walker
  if not walker then
    walker, err = self.repo:walker()
  else
    err = walker:reset()
  end
  if not walker then
    self._commits = {}
    self._commit_lines = {
      NuiLine { NuiText(string.format("Git2 Error code: %d", err), "Error") }
    }
  else
    self._walker = walker
    local i = 0
    walker:push_head()

    self._commits = {}
    for id, commit in walker:iter() do
      local parents = vim.tbl_map(
        function(p) return p:tostring(20) end,
        commit:parent_oids()
      )

      ---@type NuiGitGraphCommitNode
      local node = {
        oid = id:tostring(20),
        message = commit:message(),
        parents = parents,
      }
      table.insert(self._commits, node)

      i = i + 1
      if i == 30 then
        -- get first 30 commit only
        break
      end
    end

    local width
    self._commits, width = self.prepare_commit_node_visualisation(self._commits)
    self._commit_lines = self.draw_commit_nodes(self._commits, width)
  end
end


-- Prepares node visulasation information for each commit
---@param nodes NuiGitGraphCommitNode[] Commit Node in topo order.
---@return NuiGitGraphCommitNode[] out_nodes
---@return integer graph_width
function NuiGitGraph.prepare_commit_node_visualisation(nodes)
  ---@type {[string]: ActiveBranchItem}
  local active_branches = {} -- mapping from oid to {j, out_cols? }
  ---@type ActiveBranchItem?
  local branch
  local col_arr = utils.BitArray.new() -- bitarray to save allocated columns

  -- travel nodes sorted order
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

    -- handle branch out
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


-- Draws graph line base on column of characters
---@param cols string[]
---@param width integer padding width, if == 0, no padding-right
---@param commit_j integer? commit column
---@return NuiLine
function NuiGitGraph.draw_graph_line(cols, width, commit_j)
  local graph_line = {}
  local space_pad, space_2_pad = "   ", "  "
  local dash_pad, dash_2_pad = "───", "──"
  local dash_empty = "────"
  local space_empty = NuiText("    ")

  local draw_dash = false
  local color = ""

  local j = #cols
  if commit_j then
    j = commit_j
  end

  -- left to j
  for i = 1,j-1 do
    if cols[i] == "" then
      if draw_dash then
        table.insert(graph_line, NuiText(dash_empty)) -- TODO: coloring
      else
        table.insert(graph_line, space_empty)
      end
    else
      if cols[i] == SYMBOLS.COMMIT_BRANCH or cols[i] == "|" then
        if draw_dash then
          table.insert(graph_line, NuiText(SYMBOLS.COMMIT_BRANCH_JUMP)) -- TODO: coloring
          table.insert(graph_line, NuiText(dash_pad)) -- TODO:coloring
        else
          table.insert(graph_line, NuiText(cols[i] .. space_pad)) -- TODO coloring
        end
      else
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
        table.insert(graph_line, NuiText(symbol .. dash_pad)) -- TODO: coloring
      end
    end
  end

  -- commit symbol
  local k = #graph_line + 1
  graph_line[k] = NuiText(cols[j])
  k = k + 1
  local is_wide_commit = cols[j]:len() > 4

  -- right to j
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
        table.insert(graph_line, k, NuiText(dash_empty)) -- TODO: coloring
      else
        table.insert(graph_line, k, space_empty)
      end
    else
      if cols[i] == SYMBOLS.COMMIT_BRANCH or cols[i] == "|" then
        if draw_dash then
          table.insert(graph_line, k, NuiText(SYMBOLS.COMMIT_BRANCH_JUMP)) -- TODO: coloring
          table.insert(graph_line, k, NuiText(dash_pad)) -- TODO:coloring
        else
          table.insert(graph_line, k, NuiText(space_pad .. cols[i])) -- TODO coloring
        end
      else
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
        table.insert(graph_line, k, NuiText(dash_pad .. symbol))
      end
    end
  end

  -- padding right
  if width > #cols then
    local padding_right = NuiText(string.rep("    ", width - #cols))
    table.insert(graph_line, padding_right)
  end

  return NuiLine(graph_line)
end


---@param vis NuiGitGraphCommitNodeVis
---@return NuiLine pre_line
local function draw_graph_node_pre_line_bare(vis)
  local max_pre_j = vis.j

  if vis.start then
    max_pre_j = 1
  end

  if vis.active_cols then
    max_pre_j = math.max(max_pre_j, vis.active_cols[#vis.active_cols])
  end

  local pre_cols = utils.list_init(SYMBOLS.COMMIT_EMPTY, max_pre_j)
  utils.list_fill(pre_cols, SYMBOLS.COMMIT_BRANCH, vis.active_cols)

  if not vis.start then
    pre_cols[vis.j] = SYMBOLS.COMMIT_BRANCH
  end

  return NuiGitGraph.draw_graph_line(pre_cols, 0)
end


---@param vis NuiGitGraphCommitNodeVis
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

  return NuiGitGraph.draw_graph_line(commit_cols, width, vis.j)
end


---@param vis NuiGitGraphCommitNodeVis
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

  return NuiGitGraph.draw_graph_line(commit_cols, width, vis.j)
end


---@param vis NuiGitGraphCommitNodeVis
---@param width integer
---@param commit_line_symbol boolean?
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
      cols[vis.j] = SYMBOLS.BRANCH_UP_LEFT
    else
      cols[vis.j] = SYMBOLS.BRANCH_COMMIT_LRIGHT
    end
  else
    cols[vis.j] = SYMBOLS.CURRENT_COMMIT
  end

  return NuiGitGraph.draw_graph_line(cols, width, vis.j)
end


-- Draws commit graph similar to flog
---@param nodes NuiGitGraphCommitNode[]
---@param width integer
---@return NuiLine[] lines
function NuiGitGraph.draw_commit_nodes(nodes, width)
  local lines = {} -- output lines
  local pre_line, commit_line  = {}, {}

  for i, commit in ipairs(nodes) do
    if commit.vis then
      if commit.vis.out_cols and commit.vis.merge_cols then
        -- draw both merge and branch-out line
        pre_line = draw_graph_node_branch_out_line(commit.vis, width, true)
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

    end

    commit_line:append(" " .. utils.lines_head(commit.message))

    -- add to lines
    if i ~= 1 then
      table.insert(lines, pre_line)
    end
    table.insert(lines, commit_line)
  end

  return lines
end


-- Renders content for NuiGitGraph.
function NuiGitGraph:render()
  -- branch lines
  for i, line in ipairs(self._branch_lines) do
    line:render(self.branch_bufnr, self.ns_id, i)
  end

  -- commit panel
  local commit_lines = vim.tbl_map(
    function(line) return line:content() end,
    self._commit_lines
  )
  vim.api.nvim_buf_set_lines(
    self.commit_bufnr, 0, -1, true, commit_lines
  )
end


-- Setups keymap handlers
---@param branch_popup NuiPopup
---@param commit_popup NuiPopup
---@param map_options table
function NuiGitGraph:setup_handlers(branch_popup, commit_popup, map_options)
  -- exit func
  local commit_exit_fn = function()
    commit_popup:unmount()
  end
  commit_popup:map("n", "q", commit_exit_fn, map_options)
  commit_popup:map("n", "<esc>", commit_exit_fn, map_options)
  branch_popup:map("n", "q", commit_exit_fn, map_options)
  branch_popup:map("n", "<esc>", commit_exit_fn, map_options)
  -- commit_popup:on(event.BufLeave, exit_fn)


  -- update
  local update_fn = function()
    self:update()
    self:render()
  end
  commit_popup:map("n", "r", update_fn, map_options)
  branch_popup:map("n", "r", update_fn, map_options)

  --movement
  commit_popup:map("n", "j", "2j", map_options)
  commit_popup:map("n", "k", "2k", map_options)
  commit_popup:map("n", "h",
    function() vim.api.nvim_set_current_win(branch_popup.winid) end,
    map_options
  )
  branch_popup:map("n", "l",
    function() vim.api.nvim_set_current_win(commit_popup.winid) end,
    map_options
  )
end


NuiGitGraph.CommitNode = NuiGitGraphCommitNode


return NuiGitGraph
