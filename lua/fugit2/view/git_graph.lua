-- NUI Git graph module

local NuiLayout = require "nui.layout"
local Object = require "nui.object"

local BranchView = require "fugit2.view.components.branch_tree_view"
local LogView = require "fugit2.view.components.commit_log_view"


local BRANCH_WINDOW_WIDTH = 40


---@class NuiGitGraphView
---@field branch_popup NuiPopup Branch popup.
---@field commit_popup NuiPopup Commit popup.
---@field ns_id integer Namespace id.
---@field repo GitRepository
local GitGraph = Object("Fugit2GitGraphView")


---Inits NuiGitGraph.
---@param ns_id integer
---@param repo GitRepository
function GitGraph:init(ns_id, repo)
  if not repo then
    error("Null repo ")
  end

  self.views = {
    branch = BranchView(ns_id, BRANCH_WINDOW_WIDTH),
    log = LogView(ns_id, " 󱁉 Commits Log ")
  }

  self.repo = repo

  ---@type GitRevisionWalker?
  self._walker = nil
  ---@type NuiLine[]
  self._branch_lines, self._commit_lines = {}, {}
  ---@type GitBranch[]
  self._branches = {}
  ---@type Fugit2GitGraphCommitNode[]
  self._commits = {}

  self._layout = NuiLayout(
    {
      relative = "editor",
      position = "50%",
      size = { width = "80%", height = "80%" },
    },
    NuiLayout.Box(
      {
        NuiLayout.Box(self.views.branch.popup, { size = BRANCH_WINDOW_WIDTH }),
        NuiLayout.Box(self.views.log.popup, { grow = 1 }),
      },
      { dir = "row" }
    )
  )

  self:setup_handlers()
  self:update()
end


-- Updates git branch and commits.
function GitGraph:update()
  for i=#self._branch_lines,1,-1 do
    self._branch_lines[i] = nil
  end
  for i=#self._commit_lines,1,-1 do
    self._commit_lines[i] = nil
  end

  -- Gets all branches and head
  local branches, head, err
  head ,_ = self.repo:head()
  branches, err = self.repo:branches(true, false)
  if branches then
    self.views.branch:update(branches, head and head.name or nil)
  else
    vim.notify("[Fugit2] Failed to get branches list, error: " .. err, vim.log.levels.ERROR)
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
    vim.notify("[Fugit2] Failed to get commit, error: " .. err, vim.log.levels.ERROR)
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

      ---@type Fugit2GitGraphCommitNode
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

    self.views.log:update(self._commits)
  end
end


-- Renders content for NuiGitGraph.
function GitGraph:render()
  self.views.branch:render()
  self.views.log:render()
end


function GitGraph:mount()
  self._layout:mount()
  self.views.branch:scroll_to_active_branch()
end


-- Setups keymap handlers
function GitGraph:setup_handlers()
  local map_options = { noremap = true }
  local log_view = self.views.log
  local branch_view = self.views.branch


  -- exit func
  local exit_fn = function()
    self.repo:free_walker() -- free cached walker
    self._layout:unmount()
  end
  log_view:map("n", "q", exit_fn, map_options)
  log_view:map("n", "<esc>", exit_fn, map_options)
  branch_view:map("n", "q", exit_fn, map_options)
  branch_view:map("n", "<esc>", exit_fn, map_options)
  -- commit_popup:on(event.BufLeave, exit_fn)


  -- update
  local update_fn = function()
    self:update()
    self:render()
  end
  log_view:map("n", "r", update_fn, map_options)
  branch_view:map("n", "r", update_fn, map_options)

  --movement
  log_view:map("n", "j", "2j", map_options)
  log_view:map("n", "k", "2k", map_options)
  log_view:map("n", "h",
    function() vim.api.nvim_set_current_win(branch_view:winid()) end,
    map_options
  )
  branch_view:map("n", "l",
    function() vim.api.nvim_set_current_win(log_view:winid()) end,
    map_options
  )
end


return GitGraph
