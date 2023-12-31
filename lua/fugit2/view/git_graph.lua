-- NUI Git graph module

local event = require "nui.utils.autocmd".event
local NuiLayout = require "nui.layout"
local Object = require "nui.object"
local string_utils = require "plenary.strings"

local BranchView = require "fugit2.view.components.branch_tree_view"
local LogView = require "fugit2.view.components.commit_log_view"
local utils = require "fugit2.utils"
local git2 = require "fugit2.git2"


local BRANCH_WINDOW_WIDTH = 36
local GIT_OID_LENGTH = 16
local TAG_MAX_WIDTH = 30


---@class Fugit2GitGraphView
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
    error("[Fugit2] Null repo")
  end

  self.views = {
    branch = BranchView(ns_id, BRANCH_WINDOW_WIDTH),
    log = LogView(ns_id, " 󱁉 Commits Log ", true)
  }

  self.repo = repo

  ---@alias Fugit2GitCommitLogCache { [string]: Fugit2GitGraphCommitNode[] }
  self._git = {
    commits = {} --[[@as Fugit2GitCommitLogCache]],
    refs = {} --[[@as { [string]: string }]],
    default_branch = nil --[[@as string?]],
    default_branch_oid = nil --[[@as string?]],
    default_remote_branch = nil --[[@as string?]],
    default_remote_branch_oid = nil --[[@as string?]],
    remote_icons = {} --[[@as {[string]: string}]],
  }

  local walker, err = self.repo:walker()
  if walker then
    self._git.walker = walker
  else
    error("[Fugit2] Failed to create walker! " .. err)
  end

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
  self._last_branch_linenr = -1

  self:setup_handlers()
  self:update()
end


---Updates git branch and commits.
function GitGraph:update()
  -- clean cache
  utils.list_clear(self._git.commits)
  utils.list_clear(self._git.refs)

  local repo = self.repo
  local git = self._git

  -- Gets all branches ,head and remote default branch
  local branches, default_branch, remote, head, err

  head, _ = repo:head()
  if not head then
    vim.notify("[Fugit2] Failed to get repo head!", vim.log.levels.ERROR)
    return
  end

  branches, err = repo:branches(true, false)
  if branches then
    self.views.branch:update(branches, head.name)
  else
    vim.notify("[Fugit2] Failed to get branches list, error: " .. err, vim.log.levels.ERROR)
  end

  remote, err = repo:remote_default()
  default_branch = remote and repo:remote_default_branch(remote.name) or nil
  if remote and default_branch then
    local splitted = vim.split(default_branch, "/", { plain = true })
    git.default_branch = "refs/heads/" .. splitted[#splitted]
    git.default_remote_branch = default_branch

    local oid, _ = repo:reference_name_to_id(git.default_branch)
    git.default_branch_oid = oid and oid:tostring(GIT_OID_LENGTH) or nil

    oid, _ = repo:reference_name_to_id(default_branch)
    git.default_remote_branch_oid = oid and oid:tostring(GIT_OID_LENGTH) or nil

    git.remote_icons[remote.name] = utils.get_git_icon(remote.url)
  end

  if self._last_branch_linenr == -1 then
    self:update_log(head.name)
  else
    local node, linenr = self.views.branch:get_child_node_linenr()
    if node and linenr then
      self._last_branch_linenr = linenr
      self:update_log(node.id)
    end
  end
end


---Updates log commits
---@param refname string
function GitGraph:update_log(refname)
  local err
  local walker = self._git.walker
  local git = self._git
  local tip, commit_list, upstream, upstream_id, oid

  -- Check cache
  tip = self._git.refs[refname]
  commit_list = self._git.commits[tip]
  if tip and commit_list then
    self.views.log:update(commit_list, self._git.remote_icons)
    return
  elseif not tip then
    oid, _ = self.repo:reference_name_to_id(refname)
    if not oid then
      vim.notify("[Fugit2] Failed to resolve " .. refname, vim.log.levels.ERROR)
      return
    end

    tip = oid:tostring(GIT_OID_LENGTH)
    self._git.refs[refname] = tip

    commit_list = self._git.commits[tip]
    if commit_list then
      self.views.log:update(commit_list, self._git.remote_icons)
      return
    end
  end

  walker:reset()

  -- Get upstream if refname is not default and is branch
  if refname == git.default_branch and git.default_remote_branch then
    walker:push_ref(git.default_remote_branch)
  elseif refname ~= git.default_branch
    and git2.reference_name_namespace(refname) == git2.GIT_REFERENCE_NAMESPACE.BRANCH
  then
    upstream, _ = self.repo:branch_upstream_name(refname)
    if upstream then
      walker:push_ref(upstream)
      oid, _ = self.repo:reference_name_to_id(upstream)
      upstream_id = oid and oid:tostring(GIT_OID_LENGTH) or nil
    end
  end

  err = walker:push_ref(refname)
  if err ~= 0 then
    vim.notify(
      string.format("[Fugit2] Failed to get revision for %s!", refname),
      vim.log.levels.ERROR
    )
    return
  end

  commit_list = {}
  local i = 0
  for id, commit in walker:iter() do
    local parents = vim.tbl_map(
      function(p) return p:tostring(GIT_OID_LENGTH) end,
      commit:parent_oids()
    )

    --Retrieve tag and branches
    local refs = {}
    local tag, _ = self.repo:tag_lookup(id)
    if tag then
      refs[1] = tag
    end

    local id_str = id:tostring(GIT_OID_LENGTH)

    if git.default_branch and id_str == git.default_branch_oid then
      refs[#refs+1] = git.default_branch
    end
    if git.default_remote_branch and id_str == git.default_remote_branch_oid then
      refs[#refs+1] = git.default_remote_branch
    end
    if refname ~= git.default_branch and id_str == tip then
      refs[#refs+1] = refname
    end
    if upstream and id_str == upstream_id then
      refs[#refs+1] = upstream
    end

    ---@type Fugit2GitGraphCommitNode
    local commit_node = LogView.CommitNode(
      id:tostring(GIT_OID_LENGTH),
      commit:message(),
      commit:author(),
      parents,
      refs
    )

    i = i + 1
    commit_list[i] = commit_node

    if i >= 30 then
      -- get first 30 commit only
      break
    end
  end

  -- cache commits list with head oid
  self._git.commits[tip] = commit_list
  self.views.log:update(commit_list, self._git.remote_icons)
end


-- Renders content for NuiGitGraph.
function GitGraph:render()
  self.views.branch:render()
  self.views.log:render()
end


function GitGraph:mount()
  self._layout:mount()
  local linenr = self.views.branch:scroll_to_active_branch()
  if linenr then
    self._last_branch_linenr = linenr
  end
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

  -- refresh
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

  -- move cursor
  branch_view:on(event.CursorMoved, function()
    local node, linenr = branch_view:get_child_node_linenr()
    if node and linenr and linenr ~= self._last_branch_linenr then
      self._last_branch_linenr = linenr
      self:update_log(node.id)
      self:render()
    end
  end)
end


return GitGraph
