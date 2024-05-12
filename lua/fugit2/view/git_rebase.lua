---Main UI for Git Rebasing]
---Designated for in-memory rebasing with libgit2

local NuiLayout = require "nui.layout"
local NuiLine = require "nui.line"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"
local Object = require "nui.object"

local LogView = require "fugit2.view.components.commit_log_view"
local StatusTreeView = require "fugit2.view.components.file_tree_view"

local git2 = require "fugit2.git2"
local notifier = require "fugit2.notifier"

-- ===========
-- | Classes |
-- ===========

local SYMBOLS = {
  SQUASH_COMMIT = "󰛀",
  FIXUP_COMMIT = "󰳛",
  DROP_COMMIT = "│",
}

---@class Fugit2UIGitRebaseView
---@field layout NuiLayout
---@field rebase GitRebase
local RebaseView = Object "Fugit2UIGitRebaseView"

---@enum Fugit2UIGitRebaseAction
local RebaseAction = {
  PICK = git2.GIT_REBASE_OPERATION.PICK,
  REWORD = git2.GIT_REBASE_OPERATION.REWORD,
  EDIT = git2.GIT_REBASE_OPERATION.EDIT,
  SQUASH = git2.GIT_REBASE_OPERATION.SQUASH,
  FIXUP = git2.GIT_REBASE_OPERATION.FIXUP,
  EXEC = git2.GIT_REBASE_OPERATION.EXEC,
  BASE = 7,
  DROP = 8,
  BREAK = 9,
}

-- =================
-- | GitRebaseView |
-- =================

---@param repo GitRepository
---@param branch GitReference rebase branch ref
---@param upstream GitReference rebase upstream ref
---@param onto GitReference rebase onto ref
---@return GitRebase?
---@return GIT_ERROR
local function _init_rebase_ref(repo, branch, upstream, onto)
  local branch_commit, upstream_commit, onto_commit, err
  branch_commit, err = repo:annotated_commit_from_ref(branch)
  if not branch_commit then
    return nil, err
  end
  upstream_commit, err = repo:annotated_commit_from_ref(upstream)
  if not upstream_commit then
    return nil, err
  end
  onto_commit, err = repo:annotated_commit_from_ref(onto)
  if not onto_commit then
    return nil, err
  end

  local rebase
  rebase, err = repo:rebase_init(branch_commit, upstream_commit, onto_commit, {
    inmemory = true,
  })
  if err ~= 0 then
    return nil, err
  end

  return rebase, 0
end

---@param repo GitRepository
---@param branch string? rebase branch revspec
---@param upstream string? rebase upstream revspec
---@param onto string? rebase onto revspec
---@return GitRebase?
---@return GIT_ERROR
local function _init_rebase_revspec(repo, branch, upstream, onto)
  local branch_commit, upstream_commit, onto_commit, err

  if branch then
    branch_commit, err = repo:annotated_commit_from_revspec(branch)
    if not branch_commit then
      return nil, err
    end
  end
  if upstream then
    upstream_commit, err = repo:annotated_commit_from_revspec(upstream)
    if not upstream_commit then
      return nil, err
    end
  end
  if onto then
    onto_commit, err = repo:annotated_commit_from_revspec(onto)
    if not onto_commit then
      return nil, err
    end
  end

  local rebase
  rebase, err = repo:rebase_init(branch_commit, upstream_commit, onto_commit, {
    inmemory = true,
  })
  if err ~= 0 then
    return nil, err
  end

  return rebase, 0
end

---@param ns_id integer
---@param repo GitRepository
---@param ref_config { branch: GitReference?, upstream: GitReference?, onto: GitReference? }?
---@param revspec_config { branch: string?, upstream: string?, onto: string? }?
function RebaseView:init(ns_id, repo, ref_config, revspec_config)
  self.ns_id = ns_id
  self.repo = repo
  self._git = {}

  local rebase, err
  if ref_config then
    rebase, err = _init_rebase_ref(repo, ref_config.branch, ref_config.upstream, ref_config.onto)
    self._git.inmemory = true
  elseif revspec_config then
    rebase, err = _init_rebase_revspec(repo, revspec_config.branch, revspec_config.upstream, revspec_config.onto)
    self._git.inmemory = true
  else
    rebase, err = repo:rebase_open()
    self._git.inmemory = false
  end

  if not rebase then
    error("[Fugit2] Failed to create init!" .. err)
    return
  end
  self._git.rebase = rebase
  ---@type Fugit2GitGraphCommitNode[]
  self._git.commits = {}
  ---@type Fugit2UIGitRebaseAction[]
  self._git.actions = {}
  ---@type GitObjectId[]
  self._git.oids = {}

  -- popup views
  self.views = {}
  self.views.commits = LogView(ns_id, "  Commits ", true)
  self.views.status = NuiPopup {
    ns_id = ns_id,
    enter = false,
    focusable = false,
    border = {
      style = "rounded",
      padding = {
        top = 0,
        bottom = 0,
        left = 2,
        right = 2,
      },
      text = {
        top = NuiText(" 󱖫 Rebase status ", "Fugit2FloatTitle"),
        top_align = "left",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      swapfile = false,
      buftype = "nofile",
    },
  }
  self.layout = NuiLayout(
    {
      relative = "editor",
      position = "50%",
      size = { width = 100, height = "60%" },
    },
    NuiLayout.Box({
      NuiLayout.Box(self.views.status, { size = 4 }),
      NuiLayout.Box(self.views.commits.popup, { grow = 1 }),
    }, { dir = "col" })
  )

  self._states = {
    help_line = NuiLine {
      NuiText(
        "Actions: [p]ick, [r]e[w]ord, [s]quash, [f]ixup, [d]rop, [b]reak, [gj][C-j], [gk][C-k], []",
        "Fugit2ObjectId"
      ),
    },
  }

  self:setup_handlers()

  self:update()
  self:render()
end

---@param action Fugit2UIGitRebaseAction
---@return NuiText pre_msg text of pre message
---@return string? symbol commit symbol override
local function rebase_action_text(action)
  if action == RebaseAction.PICK then
    return NuiText("󰄵 PICK    ", "Fugit2RebasePick")
  elseif action == RebaseAction.EDIT then
    return NuiText("󰤌 EDIT    ", "Fugit2RebasePick")
  elseif action == RebaseAction.FIXUP then
    return NuiText("󰇾 FIXUP   ", "Fugit2RebaseSquash"), SYMBOLS.FIXUP_COMMIT
  elseif action == RebaseAction.SQUASH then
    return NuiText("󰶯 SQUASH  ", "Fugit2RebaseSquash"), SYMBOLS.SQUASH_COMMIT
  elseif action == RebaseAction.EXEC then
    return NuiText(" EXEC    ", "Fugit2RebasePick")
  elseif action == RebaseAction.REWORD then
    return NuiText("󰧭 REWORD  ", "Fugit2RebasePick")
  elseif action == RebaseAction.DROP then
    return NuiText("󰹎 DROP    ", "Fugit2RebaseDrop"), SYMBOLS.DROP_COMMIT
  elseif action == RebaseAction.BREAK then
    return NuiText("󰜉 BREAK   ", "Fugit2RebaseDrop"), SYMBOLS.DROP_COMMIT
  end
  return NuiText "󰜉 NONE  "
end

---Updates buffer contents based on status of libgit2 git_rebase
function RebaseView:update()
  self._states.status_line = NuiLine {
    NuiText(tostring(self._git.rebase)),
  }

  self._git.signature, _ = self.repo:signature_default()

  ---@type Fugit2GitGraphCommitNode[]
  local commits = self._git.commits
  local actions = self._git.actions
  local oids = self._git.oids
  local n_commits = self._git.rebase:noperations()

  for i = n_commits - 1, 0, -1 do
    local op = self._git.rebase:operation_byindex(i)
    if not op then
      break
    end

    local op_id, op_type = op:id(), op:type()

    local git_commit, _ = self.repo:commit_lookup(op_id)
    local message, author = "", ""
    if git_commit then
      author = git_commit:author()
      message = git_commit:message()
    end

    local rebase_text, symbol = rebase_action_text(op_type)

    local node = LogView.CommitNode(op_id:tostring(16), message, author, {}, {}, symbol, rebase_text)
    commits[n_commits - i] = node
    actions[n_commits - i] = op_type
    oids[n_commits - i] = op_id:clone()
  end
  for i = 1, #commits - 1 do
    commits[i].parents[1] = commits[i + 1].oid
  end

  self.views.commits:update(commits, {})
end

function RebaseView:render()
  self._states.status_line:render(self.views.status.bufnr, self.ns_id, 1)
  self._states.help_line:render(self.views.status.bufnr, self.ns_id, 2)

  self.views.commits:render()
end

---Starts rebase process with given user actions
function RebaseView:rebase_start()
  local actions = self._git.actions
  local oids = self._git.oids

  -- change git2 rebase action and order
  local n_commits = self._git.rebase:noperations()
  for i = 0, n_commits - 1 do
    local op = self._git.rebase:operation_byindex(i)
    if not op then
      break
    end

    local oid = oids[n_commits - i]
    if oid ~= op:id() then
      op:set_id(oid)
    end

    local action = actions[n_commits - i]
    if action >= 0 and action <= 5 then
      op:set_type(action)
    elseif action == RebaseAction.DROP then
      op:set_type(git2.GIT_REBASE_OPERATION.EXEC)
      op:set_exec(nil)
    end
  end

  -- call initial next
  self:rebase_next()
end

---Makes the next rebase operation
function RebaseView:rebase_next()
  local rebase = self._git.rebase
  local signature = self._git.signature

  local commit
  local op, err = rebase:next()
  if err == 0 then
    _, err = rebase:commit(nil, signature, nil)
    self:rebase_next()
  elseif err == git2.GIT_ERROR.GIT_ECONFLICT then
    -- conflict
    print(err)
  elseif err == git2.GIT_ERROR.GIT_ITEROVER then
    -- end of iter
    print "End"
  else
    print(err)
  end
end

---Inits status view.
---@return Fugit2GitStatusTree
function RebaseView:init_files_view()
  local status_view = StatusTreeView(self.ns_id, " 󰙅 Files ", nil, nil)
  self.views.files = status_view

  return status_view
end

---Shows git status when having conflicts.
function RebaseView:show_files()
  local files = self.views.files
  if not files then
    files = self:init_files_view()
  end

  local index
  if self._git.inmemory then
    index, _ = self._git.rebase:inmemory_index()
  else
    index, _ = self.repo:index()
  end
  if index then
  end

  self.layout:update(NuiLayout.Box({
    NuiLayout.Box(self.views.status, { size = 4 }),
    NuiLayout.Box(files.popup, { grow = 1 }),
  }, { dir = "col" }))
end

function RebaseView:setup_handlers()
  local opts = { noremap = true, nowait = true }
  local commit_view = self.views.commits
  local commits = self._git.commits
  local actions = self._git.actions
  local oids = self._git.oids

  -- main function to handle rebase action
  local action_fn = function(action)
    local _, commit_idx = commit_view:get_commit()
    if not commit_idx then
      return
    end

    actions[commit_idx] = action

    local commit = commits[commit_idx]
    commit.pre_message, commit.symbol = rebase_action_text(action)

    commit_view:update(commits)
    commit_view:render()
  end

  -- drop commit
  commit_view:map("n", { "x", "d" }, function()
    action_fn(RebaseAction.DROP)
  end, opts)

  -- break commit
  if not self._git.inmemory then
    commit_view:map("n", "b", function()
      action_fn(RebaseAction.BREAK)
    end, opts)
  else
    commit_view:map("n", "b", function()
      notifier.warn "Inmemory rebase doens't not support BREAK!"
    end, opts)
  end

  -- edit commit
  if not self._git.inmemory then
    commit_view:map("n", "e", function()
      action_fn(RebaseAction.EDIT)
    end, opts)
  else
    commit_view:map("n", "e", function()
      notifier.warn "Inmemory rebase doens't not support EDIT!"
    end, opts)
  end

  --squash commit
  commit_view:map("n", "s", function()
    action_fn(RebaseAction.SQUASH)
  end, opts)

  --fixup
  commit_view:map("n", "f", function()
    action_fn(RebaseAction.FIXUP)
  end, opts)

  -- reword
  commit_view:map("n", { "r", "w" }, function()
    action_fn(RebaseAction.REWORD)
  end, opts)

  -- pick
  commit_view:map("n", "p", function()
    action_fn(RebaseAction.PICK)
  end, opts)

  -- Reorder actions
  local reorder_fn = function(is_down)
    local _, commit_idx = commit_view:get_commit()
    if not commit_idx or (is_down and commit_idx == #commits) or (not is_down and commit_idx == 1) then
      return
    end

    local i, j -- index, i < j
    if is_down then
      i, j = commit_idx, commit_idx + 1
    else
      i, j = commit_idx - 1, commit_idx
    end

    -- swap actions
    actions[i], actions[j] = actions[j], actions[i]

    -- swap oids
    oids[i], oids[j] = oids[j], oids[i]

    -- swap commits log
    local ci, cj = commits[i], commits[j]
    if i > 1 then
      -- change pre i parents
      local c_pre = commits[i - 1]
      c_pre.parents, ci.parents = ci.parents, c_pre.parents
    else
      ci.parents = { ci.oid }
    end
    ci.parents, cj.parents = cj.parents, ci.parents
    commits[i], commits[j] = cj, ci

    -- move cursor
    local winid = commit_view:winid()
    local position = vim.api.nvim_win_get_cursor(winid)
    if is_down then
      vim.api.nvim_win_set_cursor(winid, { position[1] + 2, position[2] })
    else
      vim.api.nvim_win_set_cursor(winid, { position[1] - 2, position[2] })
    end

    -- rerender
    commit_view:update(commits)
    commit_view:render()
  end

  commit_view:map("n", { "gj", "<C-j>" }, function()
    reorder_fn(true)
  end, opts)

  commit_view:map("n", { "gk", "<C-k>" }, function()
    reorder_fn(false)
  end, opts)

  -- Movements
  commit_view:map("n", "j", "2j", opts)
  commit_view:map("n", "k", "2k", opts)

  commit_view:map("n", "<cr>", function()
    self:rebase_start()
  end, opts)
end

function RebaseView:mount()
  self.layout:mount()
end

function RebaseView:unmount()
  self._git = nil
  self.layout:unmount()
end

return RebaseView
