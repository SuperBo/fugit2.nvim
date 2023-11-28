-- NUI Git graph module


local NuiLine = require "nui.line"
local NuiText = require "nui.text"
local Object = require "nui.object"
local event = require "nui.utils.autocmd".event

local git2 = require "fugit2.git2"
local utils = require "fugit2.utils"


local SYMBOLS = {
  CURRENT_COMMIT        = "●",
  COMMIT_BRANCH         = "│ ",
  COMMIT_EMPTY          = "  ",
  COMPLEX_MERGE_1       = "┬┆",
  COMPLEX_MERGE_2       = "╰┤",
  MERGE_ALL             = "┼",
  MERGE_COMMIT          = "󰍌 ",
  MERGE_JUMP            = "┆",
  MERGE_UP_DOWN_LEFT    = "┤",
  MERGE_UP_DOWN_RIGHT   = "├",
  MERGE_UP_DOWN         = "│",
  MERGE_UP_LEFT_RIGHT   = '┴',
  MERGE_UP_LEFT         = "╯",
  MERGE_UP_RIGHT        = '╰',
  MERGE_UP              = " ",
  MERGE_DOWN_LEFT_RIGHT = "┬",
  MERGE_DOWN_LEFT       = "╮",
  MERGE_DOWN_RIGHT      = "╭",
  MERGE_LEFT_RIGHT      = "─",
  MERGE_EMPTY           = " ",
  MISSING_PARENT        = "┆ ",
  MISSING_PARENT_BRANCH = "│ ",
  MISSING_PARENT_EMPTY  = "  ",
}

---@class ActiveBranchItem
---@field j integer
---@field out_cols integer[]? optional out_cols
---@field main_merge boolean? optional flag to indicate this branch is main merge branch


-- Helper class to store graph vis information
---@class NuiGitGraphCommitNodeVis
---@field j integer graph j coordinate
---@field active_cols integer[]? current active branch j
---@field out_cols integer[]? out branches column j
---@field merge_cols integer[]? merge branches column j


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


-- Draws commit graph similar to flog
---@param nodes NuiGitGraphCommitNode[]
---@return NuiLine[] lines
local function draw_topo_commit_nodes(nodes)
  local lines = {} -- output lines
  -- TODO

  return lines
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
    error("Nil repo ")
  end

  self.repo = repo

  ---@type NuiLine[]
  self._branch_lines = {}
  ---@type GitBranch[]
  self._branches = {}

  self:update()
end


---@param nodes NuiGitGraphCommitNode[] Commit Node in topo order.
---@return NuiGitGraphCommitNode[] out_nodes
---@return integer graph_width
function NuiGitGraph.prepare_commit_node_visualisation(nodes)
  ---@type {[string]: ActiveBranchItem}
  local active_branches = {} -- mapping from oid to {j, out_cols?, main_merge?}
  ---@type ActiveBranchItem?
  local branch
  local col_arr = utils.BitArray.new() -- bitarray to save allocated columns

  -- travel nodes in topo order
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
    end

    commit.vis.j = branch.j

    if branch.out_cols then
      for _, col in ipairs(branch.out_cols) do
        col_arr:unset(col)
      end

      commit.vis.out_cols = branch.out_cols
      branch.out_cols = nil -- delete out cols of active branches
      branch.main_merge = nil
    end

    -- prepare for next iter
    if #commit.parents > 0 then
      local parent_oid = commit.parents[1]
      local parent_branch = active_branches[parent_oid]

      if parent_branch then
        -- commit is a branch child, close this branch
        local out_col = branch.j
        if branch.main_merge then
          out_col = parent_branch.j
          parent_branch.j = branch.j
        end
        if parent_branch.out_cols then
          table.insert(parent_branch.out_cols, out_col)
        else
          parent_branch.out_cols = { out_col }
        end
      else
        -- linear child
        active_branches[parent_oid] = branch
      end
    end

    if #commit.parents > 1 then
      -- merge commit
      -- first parent already allocated same j for merge commit
      branch.main_merge = true

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

      commit.vis.merge_cols = vim.list_extend(allocated_j, unset)
      for k, col in ipairs(unset) do
        active_branches[unallocated[k]] = { j = col }
      end
    end
  end

  return nodes, col_arr.n
end


-- Updates git branch / commit.
function NuiGitGraph:update()
  for i, _ in ipairs(self._branch_lines) do
    self._branch_lines[i] = nil
  end
  local lines = self._branch_lines

  -- Gets all branches
  local branches, err = self.repo:branches(true, false)
  if branches == nil then
    self._branches = {}
    lines = {
      NuiLine { NuiText(string.format("Git2 Error code: %d", err), "Error") }
    }
  else
    local branch_icon = utils.get_git_namespace_icon(git2.GIT_REFERENCE_NAMESPACE.BRANCH)
    self._branches = branches
    for i, branch in ipairs(branches) do
      lines[i] = NuiLine { NuiText( branch_icon .. branch.name ) }
    end
  end
end


-- Renders content for NuiGitGraph.
function NuiGitGraph:render()
  for i, line in ipairs(self._branch_lines) do
    line:render(self.branch_bufnr, self.ns_id, i)
  end
end


NuiGitGraph.CommitNode = NuiGitGraphCommitNode
NuiGitGraph.draw_topo_commit_nodes = draw_topo_commit_nodes


return NuiGitGraph
