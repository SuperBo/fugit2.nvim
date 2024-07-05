-- Fugit2 Git graph module

local NuiLayout = require "nui.layout"
local Object = require "nui.object"
local async = require "plenary.async"
local event = require("nui.utils.autocmd").event
local iter = require "plenary.iterators"

local BranchView = require "fugit2.view.components.branch_tree_view"
local LogView = require "fugit2.view.components.commit_log_view"
local git2 = require "fugit2.git2"
local notifier = require "fugit2.notifier"
local utils = require "fugit2.utils"

local BRANCH_WINDOW_WIDTH = 36
local GIT_OID_LENGTH = 16
local NUM_COMMIT = 30

---@enum Fugit2GitGraphEntity
local ENTITY = {
  BRANCH_LOCAL = 1,
  BRANCH_REMOTE = 2,
  BRANCH_LOCAL_REMOTE = 3,
  TAG = 4,
}

---@class Fugit2GitGraphView
---@field branch_popup NuiPopup Branch popup.
---@field commit_popup NuiPopup Commit popup.
---@field ns_id integer Namespace id.
---@field repo GitRepository
local GitGraph = Object "Fugit2GitGraphView"

GitGraph.ENTITY = ENTITY

---Inits NuiGitGraph.
---@param ns_id integer
---@param repo GitRepository
function GitGraph:init(ns_id, repo)
  if not repo then
    error "[Fugit2] Null repo"
  end

  self.ns_id = ns_id

  local views = {
    branch = BranchView(ns_id, BRANCH_WINDOW_WIDTH),
    log = LogView(ns_id, " 󱁉 Commits Log ", false),
  }
  if self._views then
    self._views = vim.tbl_extend("keep", views, self._views)
  else
    self._views = views
  end

  self.repo = repo

  ---@alias Fugit2GitCommitLogCache { [string]: Fugit2GitGraphCommitNode[] }
  self._git = {
    commits = {} --[[@as Fugit2GitCommitLogCache]],
    commits_iter_over = {} --[[@as {[string]: boolean} ]],
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
    NuiLayout.Box({
      NuiLayout.Box(self._views.branch.popup, { size = BRANCH_WINDOW_WIDTH }),
      NuiLayout.Box(self._views.log.popup, { grow = 1 }),
    }, { dir = "row" })
  )
  self._states = {
    entity = ENTITY.BRANCH_LOCAL,
    last_branch_linenr = -1,
    last_walker_tip = nil,
    walker_tip = nil,
    contents = {},
  }

  self:setup_handlers()

  local update_fn = async.wrap(function(callback)
    self:update()
    return callback()
  end, 1)
  async.run(update_fn, function()
    self:render()
  end)
end

---Updates git branch and commits.
function GitGraph:update()
  -- clean cache
  utils.list_clear(self._git.commits)
  utils.list_clear(self._git.refs)

  local repo = self.repo
  local git = self._git

  -- Gets all branches, head and remote default branch
  local default_branch, remote, head, err

  head, _ = repo:head()
  if not head then
    notifier.error "Failed to get repo head!"
    return
  end

  local entity_type = self._states.entity
  if entity_type > 0 and entity_type < ENTITY.TAG then
    self._views.branch:set_branch_title()

    local branches

    if entity_type == ENTITY.BRANCH_LOCAL then
      branches, err = repo:branches(true, false)
    elseif entity_type == ENTITY.BRANCH_REMOTE then
      branches, err = repo:branches(false, true)
    elseif entity_type == ENTITY.BRANCH_LOCAL_REMOTE then
      branches, err = repo:branches(true, true)
    end

    if branches then
      self._views.branch:update_branches(branches, head.name)
      self._states.contents = branches
      self._states.active = head.name
    else
      notifier.error("Failed to get branches list", err)
      return
    end
  elseif self._states.entity == ENTITY.TAG then
    self._views.branch:set_tag_title()

    local tags
    tags, err = repo:tag_list()
    if tags then
      table.sort(tags, function(a, b)
        return a > b
      end)
      self._states.contents = tags
      self._views.branch:update_tags(tags)
    else
      notifier.error("Failed to get git tags", err)
      return
    end
  else
    notifier.error "Wrong Git entity"
    return
  end

  remote, err = repo:remote_default()
  default_branch = remote and repo:remote_default_branch(remote.name) or nil
  if default_branch then
    local splitted = vim.split(default_branch, "/", { plain = true })
    git.default_branch = "refs/heads/" .. splitted[#splitted]
    git.default_remote_branch = default_branch

    local oid, _ = repo:reference_name_to_id(git.default_branch)
    git.default_branch_oid = oid and oid:tostring(GIT_OID_LENGTH) or nil

    oid, _ = repo:reference_name_to_id(default_branch)
    git.default_remote_branch_oid = oid and oid:tostring(GIT_OID_LENGTH) or nil
  end

  iter.iter(repo:remote_list() or {}):for_each(function(remote_name)
    local r, _ = repo:remote_lookup(remote_name)
    git.remote_icons[remote_name] = r and utils.get_git_icon(r.url) or nil
  end)

  if self._states.last_branch_linenr == -1 then
    self:update_log(head.name)
  else
    local node, linenr = self._views.branch:get_child_node_linenr()
    if node and linenr then
      self._states.last_branch_linenr = linenr
      self:update_log(node.id)
    end
  end
end

-- Clear log commits
function GitGraph:clear_log()
  self._views.log:clear()
end

---Converts git commit to Fugit2GitGraphCommitNode
---@param repo GitRepository
---@param id GitObjectId
---@param commit GitCommit
---@param tip string
---@param refname string?
---@param upstream string?
---@param upstream_id string?
---@param git table
---@return Fugit2GitGraphCommitNode
local function commit_to_node(repo, id, commit, tip, refname, upstream, upstream_id, git)
  local parents = vim.tbl_map(function(p)
    return p:tostring()
  end, commit:parent_oids())

  --Retrieve tag and branches
  local refs = {}
  local tag, _ = repo:tag_lookup(id)
  if tag then
    refs[1] = tag
  end

  local id_str = id:tostring(GIT_OID_LENGTH)

  if git.default_branch and id_str == git.default_branch_oid then
    refs[#refs + 1] = git.default_branch
  end
  if git.default_remote_branch and id_str == git.default_remote_branch_oid then
    refs[#refs + 1] = git.default_remote_branch
  end
  if refname and refname ~= git.default_branch and id_str == tip then
    refs[#refs + 1] = refname
  end
  if upstream and id_str == upstream_id then
    refs[#refs + 1] = upstream
  end

  ---@type Fugit2GitGraphCommitNode
  local commit_node = LogView.CommitNode(id:tostring(), commit:summary(), commit:author(), commit:time(), parents, refs)

  return commit_node
end

---Updates log commits
---@param refname string
function GitGraph:update_log(refname)
  local err
  local walker = self._git.walker
  local git = self._git
  local states = self._states
  local tip, commit_list, upstream, upstream_id, oid

  -- Check cache
  tip = self._git.refs[refname]
  commit_list = self._git.commits[tip]
  if tip and commit_list then
    self._views.log:update(commit_list, self._git.remote_icons)
    states.walker_tip = tip
    return
  elseif not tip then
    oid, err = self.repo:reference_name_to_id(refname)
    if not oid then
      notifier.error("Failed to resolve " .. refname, err)
      return
    end

    tip = oid:tostring(GIT_OID_LENGTH)
    self._git.refs[refname] = tip
    states.walker_tip = tip

    commit_list = self._git.commits[tip]
    if commit_list then
      self._views.log:update(commit_list, self._git.remote_icons)
      return
    end
  end

  walker:reset()
  states.last_walker_tip = tip

  -- Get upstream if refname is not default and is branch
  if refname == git.default_branch and git.default_remote_branch then
    walker:push_ref(git.default_remote_branch)
  elseif
    refname ~= git.default_branch and git2.reference_name_namespace(refname) == git2.GIT_REFERENCE_NAMESPACE.BRANCH
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
    notifier.error("Failed to get revision for " .. refname, err)
    return
  end

  commit_list = {}
  local i = 0
  for id, commit in walker:iter() do
    local commit_node = commit_to_node(self.repo, id, commit, tip, refname, upstream, upstream_id, git)

    i = i + 1
    commit_list[i] = commit_node

    if i >= NUM_COMMIT then
      -- get first 30 commit only
      break
    end
  end

  if i < NUM_COMMIT then
    self._git.commits_iter_over[tip] = true
  end

  -- cache commits list with head oid
  self._git.commits[tip] = commit_list
  self._views.log:update(commit_list, self._git.remote_icons)
end

---Loads more commits to log view.
---@param n integer number of commits to load more
function GitGraph:load_more_log(n)
  local states = self._states
  local git = self._git
  local walker = git.walker

  local tip = states.walker_tip
  local commit_list = git.commits[tip]

  if not tip or not commit_list then
    notifier.error "Failed to get current commit list"
    return
  end

  if git.commits_iter_over[tip] then
    return
  end

  if states.last_walker_tip ~= states.walker_tip then
    -- need to reset walker
    walker:reset()
    states.last_walker_tip = tip

    local last_commit = commit_list[#commit_list]
    local oid, err = git2.ObjectId.from_string(last_commit.oid)
    if not oid then
      notifier.error("Failed to construct git2 object id", err)
      return
    end

    err = walker:push(oid)
    if err ~= 0 then
      notifier.error("Failed to push oid to git walker", err)
      return
    end

    _, _, err = walker:next()
    if err == git2.GIT_ERROR.GIT_ITEROVER then
      git.commits_iter_over[tip] = true
      return
    elseif err ~= 0 then
      notifier.error("Failed to iter", err)
      return
    end
  end

  local i = 0
  for id, commit in walker:iter() do
    local commit_node = commit_to_node(self.repo, id, commit, tip, nil, nil, nil, git)

    i = i + 1
    commit_list[#commit_list + 1] = commit_node

    if i >= n then
      -- get first n commit only
      break
    end
  end

  if i < n then
    git.commits_iter_over[tip] = true
  end

  --TODO: switch to update_incremental when it is implemented
  self._views.log:update(commit_list, self._git.remote_icons)
end

-- Renders content for NuiGitGraph.
function GitGraph:render()
  self._views.branch:render()
  self._views.log:render()
end

-- Focus log view
function GitGraph:focus_log()
  self._views.log:focus()
end

function GitGraph:mount()
  self._layout:mount()
  self:focus_log()

  local linenr = self._views.branch:scroll_to_active_branch()
  if linenr then
    self._states.last_branch_linenr = linenr
  end
end

function GitGraph:unmount()
  self._layout:unmount()
  self.ns_id = nil
  self._views = nil
  self._states = nil
  self.repo = nil
  self._git = nil
  self._layout = nil
  self.closed = true
end

---Set callback to be called when user select commit
---@param callback fun(commit: Fugit2GitGraphCommitNode)
function GitGraph:on_commit_select(callback)
  local log_view = self._views.log
  self._commit_select_fn = callback

  -- commit select
  log_view:map("n", { "<cr>", "<space>" }, function()
    local commit = self._views.log:get_commit()
    if commit then
      self:unmount()
      callback(commit)
    end
  end, { noremap = true, nowait = true })
end

---Set call be called when user select branch
---@param callback fun(branch: string)
function GitGraph:on_branch_select(callback)
  local branch_view = self._views.branch
  self._branch_select_fn = callback

  -- branch select
  branch_view:unmap("n", { "<cr>", "<space>" })
  branch_view:map("n", { "<cr>", "<space>" }, function()
    local node, _ = branch_view:get_child_node_linenr()
    if node and node.id then
      self:unmount()
      callback(node.id)
    end
  end, { noremap = true, nowait = true })
end

-- Setups keymap handlers
function GitGraph:setup_handlers()
  local map_options = { noremap = true, nowait = true }
  local log_view = self._views.log
  local branch_view = self._views.branch

  -- exit func
  local exit_fn = function()
    self.repo:free_walker() -- free cached walker
    self:unmount()
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
  log_view:map("n", "h", function()
    vim.api.nvim_set_current_win(branch_view:winid())
  end, map_options)
  branch_view:map("n", { "l", "<cr>", "<space>" }, function()
    vim.api.nvim_set_current_win(log_view:winid())
  end, map_options)

  -- move cursor
  branch_view:on(event.CursorMoved, function()
    local node, linenr = branch_view:get_child_node_linenr()
    if node and linenr and linenr ~= self._states.last_branch_linenr then
      self._states.last_branch_linenr = linenr
      self:update_log(node.id)
      self:render()
    end
  end)

  -- copy commit id
  log_view:map("n", "yy", function()
    local commit, _ = log_view:get_commit()
    if commit then
      vim.fn.setreg("0", commit.oid)
    end
  end, map_options)

  log_view:map("n", "yc", function()
    local commit, _ = log_view:get_commit()
    if commit then
      vim.fn.setreg("+", commit.oid)
    end
  end, map_options)

  -- log lazy load handling
  log_view:on(event.WinScrolled, function(ev)
    local winid = tonumber(ev.file or ev.match)
    local num_lines = vim.api.nvim_buf_line_count(ev.buf)
    local last_visible_line = vim.fn.line("w$", winid)
    if last_visible_line >= num_lines then
      -- lazy load
      self:load_more_log(20)
      self:render()
    end
  end)
end

return GitGraph
