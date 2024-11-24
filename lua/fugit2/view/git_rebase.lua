---Main UI for Git Rebasing]
---Designated for in-memory rebasing with libgit2

local NuiLayout = require "nui.layout"
local NuiLine = require "nui.line"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"
local Object = require "nui.object"

local LogView = require "fugit2.view.components.commit_log_view"
local Menu = require "fugit2.view.components.menus"

local git2 = require "fugit2.git2"
local git_rebase_helper = require "fugit2.core.git_rebase_helper"
local notifier = require "fugit2.notifier"
local utils = require "fugit2.utils"

-- ===========
-- | Classes |
-- ===========

local GIT_OID_LENGTH = 8

local SYMBOLS = {
  SQUASH_COMMIT = "󰛀",
  FIXUP_COMMIT = "󰳛",
  DROP_COMMIT = "│",
}

---@class Fugit2UIGitRebaseView
---@field layout NuiLayout
---@field rebase GitRebase
local RebaseView = Object "Fugit2UIGitRebaseView"

local RebaseAction = git_rebase_helper.GIT_REBASE_OPERATION

---@alias Fugit2UIGitRebaseMessage {old: string, new: string}

---@class Fugit2UIGitRebaseInfo
---@field branch GitObjectId
---@field upstream GitObjectId
---@field onto GitObjectId
---@field onto_name string

-- =================
-- | GitRebaseView |
-- =================

---@param repo GitRepository
---@param branch GitAnnotatedCommit?
---@param upstream GitAnnotatedCommit
---@param onto GitAnnotatedCommit?
---@return Fugit2UIGitRebaseInfo
local function _init_rebase_info(repo, branch, upstream, onto)
  local upstream_id = upstream:id()
  local onto_name = git_rebase_helper.git_rebase_onto_name(upstream, onto)

  if not branch then
    -- get head as branch
    local err
    branch, err = repo:annotated_commit_from_revspec "HEAD"
    if not branch then
      error("[Fugit2] Failed to get HEAD commit, code " .. err)
    end
  end

  return {
    upstream = upstream_id,
    branch = branch:id(),
    onto = onto and onto:id() or upstream_id,
    onto_name = onto_name,
  }
end

---@param repo GitRepository
---@param branch GitReference rebase branch ref
---@param upstream GitReference rebase upstream ref
---@param onto GitReference rebase onto ref
---@return GitRebase?
---@return Fugit2UIGitRebaseInfo?
---@return GIT_ERROR
local function _init_rebase_ref(repo, branch, upstream, onto)
  local rebase, info, branch_commit, upstream_commit, onto_commit, err
  branch_commit, err = repo:annotated_commit_from_ref(branch)
  if not branch_commit then
    return nil, nil, err
  end
  upstream_commit, err = repo:annotated_commit_from_ref(upstream)
  if not upstream_commit then
    return nil, nil, err
  end
  onto_commit, err = repo:annotated_commit_from_ref(onto)
  if not onto_commit then
    return nil, nil, err
  end

  rebase, err = repo:rebase_init(branch_commit, upstream_commit, onto_commit, {
    inmemory = true,
  })
  if err ~= 0 then
    return nil, nil, err
  end

  info = _init_rebase_info(repo, branch_commit, upstream_commit, onto_commit)

  return rebase, info, 0
end

---@param repo GitRepository
---@param branch string? rebase branch revspec
---@param upstream string rebase upstream revspec
---@param onto string? rebase onto revspec
---@return GitRebase?
---@return Fugit2UIGitRebaseInfo?
---@return GIT_ERROR
local function _init_rebase_revspec(repo, branch, upstream, onto)
  local rebase, info, branch_commit, upstream_commit, onto_commit, err

  if branch then
    branch_commit, err = repo:annotated_commit_from_revspec(branch)
    if not branch_commit then
      return nil, nil, err
    end
  end
  if upstream then
    upstream_commit, err = repo:annotated_commit_from_revspec(upstream)
    if not upstream_commit then
      return nil, nil, err
    end
  end
  if onto then
    onto_commit, err = repo:annotated_commit_from_revspec(onto)
    if not onto_commit then
      return nil, nil, err
    end
  end

  rebase, err = repo:rebase_init(branch_commit, upstream_commit, onto_commit, {
    inmemory = true,
  })
  if err ~= 0 then
    return nil, nil, err
  end

  info = _init_rebase_info(repo, branch_commit, upstream_commit, onto_commit)

  return rebase, info, 0
end

---@param ns_id integer
---@param repo GitRepository
---@param ref_config { branch: GitReference?, upstream: GitReference?, onto: GitReference? }?
---@param revspec_config { branch: string?, upstream: string?, onto: string? }?
function RebaseView:init(ns_id, repo, ref_config, revspec_config)
  self.ns_id = ns_id
  self.repo = repo
  self._git = {}

  local rebase, rebase_info, err
  if ref_config then
    rebase, rebase_info, err = _init_rebase_ref(repo, ref_config.branch, ref_config.upstream, ref_config.onto)
    self._git.inmemory = true
  elseif revspec_config then
    rebase, rebase_info, err =
      _init_rebase_revspec(repo, revspec_config.branch, revspec_config.upstream, revspec_config.onto)
    self._git.inmemory = true
  else
    rebase, err = repo:rebase_open()
    self._git.inmemory = false

    if rebase then
      local onto = rebase:onto_id()
      local branch = rebase:orig_head_id()
      rebase_info = {
        branch = branch,
        onto = onto,
        upstream = onto,
        onto_name = rebase:onto_name(),
      }
    end
  end

  if not rebase then
    error("[Fugit2] Failed to create libgit2 rebase, code: " .. err)
    return
  end
  self._git.rebase = rebase
  self._git.rebase_info = rebase_info
  self._git.rebase_finished = false
  ---@type Fugit2GitGraphCommitNode[]
  self._git.commits = {}
  ---@type FUGIT2_GIT_REBASE_OPERATION[]
  self._git.actions = {}
  ---@type GitObjectId[]
  self._git.oids = {}
  ---@type {[string]: Fugit2UIGitRebaseMessage}
  self._git.messages = {}
  ---@type string?
  self._git.current_oid = nil
  ---@type number
  self._git.current_index = 1
  ---@type GitObjectId?
  self._git.last_commit_id = nil

  -- popup views
  self.views = {}
  self.views.commits = LogView(ns_id, "  Commits ", true)
  self.views.status = NuiPopup {
    ns_id = ns_id,
    enter = false,
    focusable = false,
    border = {
      style = "rounded",
      padding = utils.PX_2,
      text = {
        top = NuiText(" 󱖫 Rebase status ", "Fugit2FloatTitle"),
        top_align = "left",
      },
    },
    win_options = {
      winhighlight = utils.WIN_HIGHLIGHT,
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      swapfile = false,
      buftype = "nofile",
    },
  }
  self.views.input = self:_init_input_popup()

  self.boxes = {
    main = NuiLayout.Box({
      NuiLayout.Box(self.views.status, { size = 4 }),
      NuiLayout.Box(self.views.commits.popup, { grow = 1 }),
    }, { dir = "col" }),
    input = NuiLayout.Box({
      NuiLayout.Box(self.views.status, { size = 4 }),
      NuiLayout.Box(self.views.input, { size = 5 }),
      NuiLayout.Box(self.views.commits.popup, { grow = 1 }),
    }, { dir = "col" }),
  }
  self.layout = NuiLayout({
    relative = "editor",
    position = "50%",
    size = { width = 100, height = "60%" },
  }, self.boxes.main)

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

---@param action FUGIT2_GIT_REBASE_OPERATION
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

---@return NuiPopup
function RebaseView:_init_input_popup()
  local input_popup = NuiPopup {
    ns_id = self.ns_id,
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      padding = utils.PX_1,
      text = {
        top = NuiText(" Reword commit ", "Fugit2MessageHeading"),
        top_align = "left",
        bottom = NuiText("[Ctrl-c][󱊷 ][q]uit, [Ctrl 󰌑 ][󰌑 ]", "FloatFooter"),
        bottom_align = "right",
      },
    },
    win_options = {
      winhighlight = utils.WIN_HIGHLIGHT,
    },
    buf_options = {
      modifiable = true,
      filetype = "gitcommit",
    },
  }

  local opts = { noremap = true, nowait = true }

  -- keep current reword
  local exit_fn = function()
    self.views.commits:focus()
    self.layout:update(self.boxes.main)
  end

  -- update new message
  local enter_fn = function()
    local lines = vim.api.nvim_buf_get_lines(input_popup.bufnr, 0, -1, true)
    local new_message = vim.trim(table.concat(lines, "\n"))
    local message, err = git2.message_prettify(new_message)
    if not message then
      notifier.error("Can't prettify commit message", err)
      return
    end

    local messages = self._git.messages
    local oid = self._git.current_oid
    if not oid then
      notifier.error "Current commit is not set"
      return
    end

    local _, commit_idx = self.views.commits:get_commit()
    if not commit_idx then
      notifier.error "Can't retrieve current commit!"
      return
    end

    self._git.actions[commit_idx] = RebaseAction.REWORD
    local commit = self._git.commits[commit_idx]
    commit.pre_message, commit.symbol = rebase_action_text(RebaseAction.REWORD)
    messages[oid] = { old = commit.message, new = message }
    commit.message = utils.lines_head(message)

    self.views.commits:update(self._git.commits)
    self.views.commits:render()

    self.views.commits:focus()
    self.layout:update(self.boxes.main)
  end

  input_popup:map("n", { "<esc>", "q" }, exit_fn, opts)
  input_popup:map("i", "<C-c>", function()
    vim.cmd.stopinsert()
    exit_fn()
  end, opts)
  input_popup:map("n", "<cr>", enter_fn, opts)
  input_popup:map("i", "<C-cr>", function()
    vim.cmd.stopinsert()
    enter_fn()
  end, opts)

  return input_popup
end

---Updates buffer contents based on status of libgit2 git_rebase
function RebaseView:update()
  local git = self._git
  if git.inmemory then
    self._states.status_line = NuiLine {
      NuiText(
        string.format(
          "INMEMORY Rebase %s..%s onto %s",
          git.rebase_info.branch:tostring(8),
          git.rebase_info.upstream:tostring(8),
          git.rebase_info.onto_name
        )
      ),
    }
  else
    self._states.status_line = NuiLine {
      NuiText(tostring(self._git.rebase)),
    }
  end

  self._git.signature, _ = self.repo:signature_default()
  if not self._git.signature then
    error "[Fugit2] Can't get repo default author!"
  end

  ---@type Fugit2GitGraphCommitNode[]
  local commits = git.commits
  local actions = git.actions
  local oids = git.oids
  local n_commits = git.rebase:noperations()
  local rebase = git.rebase
  local current_i = tonumber(git.rebase:operation_current())
  if current_i >= n_commits then
    current_i = 0
  end
  local n_remain_commits = git.rebase_finished and 0 or n_commits - current_i

  utils.list_clear(actions)

  -- curent rebase node
  for i = n_commits - 1, current_i, -1 do
    local op = rebase:operation_byindex(i)
    if not op then
      break
    end

    local op_id, op_type = op:id(), op:type()

    local git_commit, _ = self.repo:commit_lookup(op_id)
    local message, author, time = "", "", {}
    if git_commit then
      author = git_commit:author()
      message = git_commit:summary()
      time = git_commit:time()
    end

    local rebase_text, symbol = rebase_action_text(op_type)

    local node = LogView.CommitNode(op_id:tostring(GIT_OID_LENGTH), message, author, time, {}, {}, symbol, rebase_text)
    commits[n_remain_commits - i] = node
    actions[n_remain_commits - i] = op_type
    oids[n_remain_commits - i] = op_id:clone()
  end

  local i = n_remain_commits + 1
  -- finished rebase nodes
  if git.last_commit_id then
    -- walk through commits
    local err
    ---@type GitRevisionWalker?
    local walker = git.walker
    if not walker then
      walker, err = self.repo:walker()
      if walker then
        git.walker = walker
      end
    end

    if not walker then
      error("[Fugit2] Failed to create walker! " .. err)
    end

    walker:reset()
    walker:push(git.last_commit_id)
    walker:hide(git.rebase_info.upstream)

    for id, commit in walker:iter() do
      local node = LogView.CommitNode(
        id:tostring(GIT_OID_LENGTH),
        commit:summary(),
        commit:author(),
        commit:time(),
        {},
        {},
        nil
      )
      commits[i] = node
      i = i + 1
    end
  end

  -- draw onto node
  local onto_commit, _ = self.repo:commit_lookup(git.rebase_info.onto)
  if onto_commit then
    local node = LogView.CommitNode(
      onto_commit:id():tostring(GIT_OID_LENGTH),
      onto_commit:summary(),
      onto_commit:author(),
      onto_commit:time(),
      {},
      {},
      nil
    )
    commits[i] = node
    i = i + 1
  end

  for j = i + 1, #commits do
    commits[j] = nil
  end

  for j = 1, #commits - 1 do
    commits[j].parents[1] = commits[j + 1].oid
  end

  self.views.commits:update(commits, {})
end

function RebaseView:render()
  local status_bufnr = self.views.status.bufnr
  vim.api.nvim_buf_set_option(status_bufnr, "readonly", false)
  vim.api.nvim_buf_set_option(status_bufnr, "modifiable", true)
  self._states.status_line:render(status_bufnr, self.ns_id, 1)
  self._states.help_line:render(status_bufnr, self.ns_id, 2)
  vim.api.nvim_buf_set_option(status_bufnr, "readonly", true)
  vim.api.nvim_buf_set_option(status_bufnr, "modifiable", false)

  self.views.commits:render()
end

-- Starts rebase process with user actions
function RebaseView:rebase_start()
  local git = self._git
  local actions = git.actions
  local oids = git.oids
  local rebase = git.rebase

  -- change git2 rebase action and order
  local n_commits = rebase:noperations()
  for i = 0, n_commits - 1 do
    local op = rebase:operation_byindex(i)
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

  git.current_index = #git.commits - 1 -- ignore base commit

  -- remove mapping
  local commit_view = self.views.commits
  commit_view:unmap("n", {
    "r",
    "w",
    "x",
    "d",
    "b",
    "e",
    "s",
    "f",
    "p",
    "gj",
    "<C-j>",
    "gk",
    "<C-k>",
  })

  -- call rebase
  self:rebase_continue()
end

-- Continues a paused rebase action
function RebaseView:rebase_continue()
  local git = self._git
  local actions = git.actions
  local commits = git.commits
  local rebase = git.rebase
  local signature = git.signature

  local err = 0
  local commit_idx = git.current_index
  local op, message, commit_id
  while err == 0 do
    local action = actions[commit_idx]
    if action == RebaseAction.DROP then
      op, err = rebase:skip()
      if op then
        table.remove(commits, commit_idx)
        table.remove(actions, commit_idx)

        if commit_idx > #commits then
          utils.list_clear(commits[#commits].parents)
        elseif commit_idx > 1 then
          commits[commit_idx - 1].parents[1] = commits[commit_idx].oid
        end

        commit_id = nil
      end
    else
      op, err = rebase:next()
      if op then
        local op_type = op:type()
        if op_type == git2.GIT_REBASE_OPERATION.REWORD then
          message = git.messages[op:id():tostring(8)].new
        else
          message = nil
        end

        commit_id, err = rebase:commit(nil, signature, message)
        if commit_id then
          git.last_commit_id = commit_id
        end
      end
    end

    commit_idx = commit_idx - 1
  end

  git.current_index = commit_idx

  if err == git2.GIT_ERROR.GIT_ITEROVER then
    self:rebase_finish()
  elseif err == git2.GIT_ERROR.GIT_ECONFLICT and commit_id then
    self:rebase_has_conflicts(commit_idx, commit_id)
  elseif op then
    notifier.error("Error when rebase " .. op:id():tostring(), err)
    self:rebase_abort()
  else
    notifier.error("Error when rebase", err)
    self:rebase_abort()
  end
end

-- Finish rebase action.
function RebaseView:rebase_finish()
  local states = self._states

  -- finish rebase
  local err = self._git.rebase:finish(self._git.signature)
  if err ~= 0 then
    notifier.error("Failed to finish rebase", err)
    states.help_line = NuiLine { NuiText("Git rebase error " .. err, "Fugit2Untracked") }
    self:render()
    return
  end

  self._git.rebase_finished = true

  local last_commit_id = self._git.last_commit_id
  if self._git.inmemory and last_commit_id then
    -- update head to new commit
    local last_commit
    last_commit, err = self.repo:commit_lookup(last_commit_id)

    if last_commit then
      err = self.repo:update_head_for_commit(last_commit_id, utils.lines_head(last_commit:message()), "rebase: ")
    end

    if err ~= 0 then
      notifier.error("Failed to update head", err)
      states.help_line = NuiLine { NuiText("Git rebase error " .. err, "Fugit2Untracked") }
      self:render()
      return
    end
  end

  notifier.info "Rebase successfully"
  states.help_line = NuiLine { NuiText("Rebase successfully", "Fugit2Staged") }

  self:update()
  self:render()

  -- TODO: remap to Finish flow
  -- self:unmount()
end

-- Rebase action has some conflicts, need to resolve or abort.
---@param commit_idx integer git commit index at which rebase has conflicts
---@param oid GitObjectId current git rebase commit oid
function RebaseView:rebase_has_conflicts(commit_idx, oid)
  local commits = self._git.commits
  commits[commit_idx].pre_message = NuiText(" CONFLICT", "Fugit2Error")

  self.views.commits:update(commits)
  self.views.commits:render()

  -- Show confirm
  local resolve_confirm = Menu.Confirm(
    self.ns_id,
    NuiLine {
      NuiText "Having conflicts, do you want to resolve it?",
    }
  )
  resolve_confirm:on_yes(function()
    local GitDiff = require "fugit2.view.git_diff"
    local index, head
    if self._git.inmemory then
      index, _ = self._git.rebase:inmemory_index()
      head, _ = self.repo:commit_lookup(oid)
    else
      index, _ = self.repo:index()
    end
    if index then
      local git_diff = GitDiff(self.ns_id, self.repo, index, head)
      git_diff:mount()
    else
      notifier.error "Can't retrieve git index"
    end
  end)
  resolve_confirm:mount()
end

-- Abort rebase action
function RebaseView:rebase_abort()
  local err = self._git.rebase:abort()
  if err ~= 0 then
    notifier.error("Failed to abort rebase action", err)
  end

  self:unmount()
end

---Inits status view.
---@return Fugit2GitStatusTree
-- function RebaseView:_init_files_view()
--   local status_view = StatusTreeView(self.ns_id, " 󰙅 Files ", nil, nil)
--   self.views.files = status_view
--
--   return status_view
-- end

-- Shows git status when having conflicts.
-- function RebaseView:show_files()
--   local files = self.views.files
--   if not files then
--     files = self:init_files_view()
--   end
--
--   local index
--   if self._git.inmemory then
--     index, _ = self._git.rebase:inmemory_index()
--   else
--     index, _ = self.repo:index()
--   end
--   if index then
--   end
--
--   self.layout:update(NuiLayout.Box({
--     NuiLayout.Box(self.views.status, { size = 4 }),
--     NuiLayout.Box(files.popup, { grow = 1 }),
--   }, { dir = "col" }))
-- end

function RebaseView:setup_handlers()
  local opts = { noremap = true, nowait = true }
  local commit_view = self.views.commits
  local input_view = self.views.input
  local commits = self._git.commits
  local actions = self._git.actions
  local oids = self._git.oids
  local messages = self._git.messages
  local git = self._git

  -- main function to handle rebase action
  local action_fn = function(action)
    local _, commit_idx = commit_view:get_commit()
    if not commit_idx or commit_idx == #commits then
      return
    end

    local commit = commits[commit_idx]

    if action == RebaseAction.REWORD then
      git.current_oid = commit.oid
      input_view.border:set_text("top", NuiText(" Reword commit " .. commit.oid, "Fugit2MessageHeading"))
      vim.api.nvim_buf_set_lines(self.views.input.bufnr, 0, -1, true, { commit.message })
      self.layout:update(self.boxes.input)
      vim.api.nvim_win_set_cursor(self.views.input.winid, { 1, commit.message:len() })
      return
    elseif action == RebaseAction.BREAK then
      -- drop following commits
      for i = 1, commit_idx - 1 do
        actions[i] = RebaseAction.DROP
        local ci = commits[i]
        ci.pre_message, ci.symbol = rebase_action_text(RebaseAction.DROP)
        local m = messages[ci.oid]
        if m then
          ci.message = m.old
          messages[ci.oid] = nil
        end
      end

      action = RebaseAction.PICK
    end

    actions[commit_idx] = action
    commit.pre_message, commit.symbol = rebase_action_text(action)

    local m = messages[commit.oid]
    if m then
      commit.message = m.old
      messages[commit.oid] = nil
    end

    commit_view:update(commits)
    commit_view:render()
  end

  -- drop commit
  commit_view:map("n", { "x", "d" }, function()
    action_fn(RebaseAction.DROP)
  end, opts)

  -- break commit
  commit_view:map("n", "b", function()
    action_fn(RebaseAction.BREAK)
  end, opts)

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

  -- Move cursor
  commit_view:map("n", "j", "2j", opts)
  commit_view:map("n", "k", "2k", opts)

  commit_view:map("n", "<cr>", function()
    self:rebase_start()
  end, opts)
  commit_view:map("n", { "<esc>", "q" }, function()
    self:unmount()
  end, opts)
end

function RebaseView:mount()
  self.layout:mount()
end

function RebaseView:unmount()
  self._git.last_commit_id = nil
  self._git.walker = nil
  self._git.rebase = nil
  self._git.rebase_info = nil
  self._git = nil
  self.repo = nil
  self.layout:unmount()
end

return RebaseView
