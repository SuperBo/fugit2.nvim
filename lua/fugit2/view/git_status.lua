-- Fugit2 Git Status module

local uv = vim.uv or vim.loop

local NuiLayout = require "nui.layout"
local NuiLine = require "nui.line"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"
local Path = require "plenary.path"
local PlenaryJob = require "plenary.job"
local async = require "plenary.async"
local async_utils = require "plenary.async.util"
local event = require("nui.utils.autocmd").event

local GitStatusDiffBase = require "fugit2.view.git_base_view"
local GitStatusTree = require "fugit2.view.components.file_tree_view"
local LogView = require "fugit2.view.components.commit_log_view"
local TreeBase = require "fugit2.view.components.base_tree_view"
local UI = require "fugit2.view.components.menus"
local git2 = require "fugit2.git2"
local git_gpg = require "fugit2.core.git_gpg"
local notifier = require "fugit2.notifier"
local utils = require "fugit2.utils"

-- ===================
-- | Libgit2 options |
-- ===================

local SERVER_CONNECT_TIMEOUT = 12000
local SERVER_TIMEOUT = 15000
local COMMAND_QUEUE_WAIT_TIME = SERVER_TIMEOUT * 4
local COMMAND_QUEUE_MAX = 8

git2.set_opts(git2.GIT_OPT.SET_SERVER_CONNECT_TIMEOUT, SERVER_CONNECT_TIMEOUT)
git2.set_opts(git2.GIT_OPT.SET_SERVER_TIMEOUT, SERVER_TIMEOUT)

-- local FILE_WINDOW_WIDTH = 100
local GIT_LOG_MAX_COMMITS = 8

-- ======================
-- | Helper enum buffer |
-- ======================

---@enum Fugit2GitStatusCommitMode
local CommitMode = {
  CREATE = 1,
  REWORD = 2,
  EXTEND = 3,
  AMEND = 4,
}

---@enum Fugit2GitStatusBranchMode
local BranchMode = {
  CREATE = 1,
  CREATE_CHECKOUT = 2,
}

---@enum Fugit2GitStatusMenu
local Menu = {
  BRANCH = 1,
  COMMIT = 2,
  DIFF = 3,
  FETCH = 4,
  PULL = 5,
  PUSH = 6,
  REBASE = 7,
  FORGE = 8,
}

-- ======================
-- | Helper static func |
-- ======================

---@param git_path string
---@param git_file string
---@param linenr integer?
local function open_file(git_path, git_file, linenr)
  local cwd = vim.fn.getcwd()
  local current_file = vim.api.nvim_buf_get_name(0)

  local file_path = Path:new(git_path) / vim.fn.fnameescape(git_file)

  if tostring(file_path) ~= current_file then
    local open_path = file_path:make_relative(cwd)
    if linenr then
      vim.cmd(string.format("edit %s|%d", open_path, linenr))
    else
      vim.cmd.edit(open_path)
    end
  elseif linenr then
    vim.api.nvim_win_set_cursor(0, { linenr, 0 })
  end
end

-- ===================
-- | Main git status |
-- ===================

---@enum Fugit2GitStatusSidePanel
local SidePanel = {
  NONE = 0,
  PATCH_VIEW = 1,
}

---@class Fugit2GitStatusView: Fugit2GitStatusDiffBase
local GitStatus = GitStatusDiffBase:extend "Fugit2GitStatusView"

---Inits GitStatus.
---@param ns_id integer
---@param repo GitRepository
---@param last_window integer
---@param current_file string
---@param opts Fugit2Config
function GitStatus:init(ns_id, repo, last_window, current_file, opts)
  GitStatusDiffBase.init(self, ns_id, repo)

  self.opts = opts

  self.closed = false
  ---@class Fugit2GitStatusGitStates
  ---@field path string
  ---@field head GitStatusHead?
  ---@field upstream GitStatusUpstream?
  ---@field ahead integer
  ---@field behind integer
  ---@field index_updated boolean Whether git status is updated
  ---@field head_tree GitTree
  ---@field unstaged_diff { [string]: GitPatch }
  ---@field staged_diff { [string]: GitPatch }
  ---@field remote { name: string, url: string, push_url: string? }?
  ---@field remote_icons { [string]: string }?
  ---@field push_target { name: string, oid: string, ahead: integer, behind: integer }?
  ---@field signature GitSignature?
  ---@field walker GitRevisionWalker?
  ---@field config GitConfig?
  self._git = vim.tbl_extend("force", self._git, {
    head = nil,
    ahead = 0,
    behind = 0,
    index_updated = false,
    unstaged_diff = {},
    staged_diff = {},
    config = nil,
  })

  if self.repo ~= nil then
    local sig, walker

    sig, _ = self.repo:signature_default()
    if sig then
      self._git.signature = sig
    end

    walker, _ = self.repo:walker()
    if walker then
      self._git.walker = walker
    end
  else
    error "[Fugit2] Null repo"
  end

  local default_padding = {
    top = 0,
    bottom = 0,
    left = 1,
    right = 1,
  }

  local win_hl = "Normal:Normal,FloatBorder:FloatBorder"
  local buf_readonly_opts = {
    modifiable = false,
    readonly = true,
    swapfile = false,
    buftype = "nofile",
  }

  -- create popups/views
  self._views = {}
  self.info_popup = NuiPopup {
    ns_id = ns_id,
    enter = false,
    focusable = true,
    border = {
      style = "rounded",
      padding = { top = 1, bottom = 1, left = 1, right = 1 },
      text = {
        top = NuiText(" 󱖫 Status ", "Fugit2FloatTitle"),
        top_align = "left",
      },
    },
    win_options = {
      winhighlight = win_hl,
      wrap = false,
    },
    buf_options = vim.tbl_extend("force", buf_readonly_opts, {
      filetype = "fugit2-status-info",
    }),
  }

  self.command_popup = NuiPopup {
    ns_id = ns_id,
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      padding = default_padding,
      text = {
        top = NuiText("  Console ", "Fugit2FloatTitle"),
        top_align = "left",
        bottom = NuiText("[esc][q]uit", "FloatFooter"),
        bottom_align = "right",
      },
    },
    win_options = {
      winhighlight = win_hl,
    },
    buf_options = vim.tbl_extend("force", buf_readonly_opts, {
      filetype = "fugit2-status-command",
    }),
  }

  ---@type Fugit2CommitLogView
  self._views.commits = LogView(self.ns_id, "  Commits ", false)
  ---@type Fugit2GitStatusTree
  self._views.files = GitStatusTree(self.ns_id, " 󰙅 Files ", "[b]ranches [c]ommits [d]iff", opts.content_width)

  -- menus
  self._prompts = {
    amend_confirm = UI.Confirm(
      self.ns_id,
      NuiLine { NuiText "This commit has already been pushed to upstream, do you really want to modify it?" }
    ),
    discard_confirm = UI.Confirm(self.ns_id, NuiLine { NuiText "󰮈 Discard changes, are you sure?" }),
  }
  ---@type { [integer]: Fugit2UITransientMenu }
  self._menus = {}

  -- setup others

  ---@type NuiLine[]
  self._status_lines = {}

  -- setup layout
  ---@type { [string]: NuiLayout.Box }
  self._boxes = {
    main = NuiLayout.Box({
      NuiLayout.Box(self.info_popup, { size = 6 }),
      NuiLayout.Box(self._views.files.popup, { grow = 1, size = 10 }),
      NuiLayout.Box(self._views.commits.popup, { size = 10 }),
    }, { dir = "col" }),
    main_row = NuiLayout.Box(self._views.files.popup, { grow = 1 }),
  }
  self._layout_opts = {
    main = {
      relative = "editor",
      position = "50%",
      size = { width = self.opts.width, height = self.opts.height },
    },
    diff = {
      position = "50%",
      size = { width = self.opts.max_width, height = self.opts.height },
    },
  }
  local layout_opt = self.opts.show_patch and self._layout_opts.diff or self._layout_opts.main
  self._layout = NuiLayout(layout_opt, self._boxes.main)

  -- state variables for UI
  ---@class Fugit2GitStatusInternal
  ---@field last_window integer
  ---@field branch_mode Fugit2GitStatusBranchMode
  ---@field branch_ref string?
  ---@field commit_mode Fugit2GitStatusCommitMode
  ---@field commit_args string[]?
  ---@field side_panel Fugit2GitStatusSidePanel
  ---@field last_patch_line integer
  ---@field patch_staged_shown boolean
  ---@field patch_unstaged_shown boolean
  ---@field current_text NuiText
  ---@field upstream_text NuiText?
  ---@field timer uv_timer_t?
  ---@field job Job?
  ---@field command_queue integer[]
  ---@field jobs Job[]
  ---@field file_entry_width integer
  self._states = {
    last_window = last_window,
    current_file = current_file,
    branch_mode = BranchMode.CREATE,
    commit_mode = CommitMode.CREATE,
    side_panel = SidePanel.NONE,
    file_entry_width = opts.content_width,
    command_queue = {},
  }

  -- keymaps
  self:setup_handlers()

  self:update(function()
    self:render()
    self:scroll_to_active_file()
    if opts.show_patch then
      vim.schedule(function()
        self:show_patch_for_active_file()
      end)
    end
  end)
end

---@param git Fugit2GitStatusGitStates
---@param menu_items Fugit2UITransientItem[]
---@return Fugit2UITransientItem[]
local function prepare_pull_push_items(git, menu_items)
  if git.remote and not git.push_target then
    local text = utils.get_git_icon(git.remote.url) .. git.remote.name .. "/" .. git.head.name
    menu_items[2].texts[1] = NuiText(text, "Fugit2Heading")
  elseif git.remote and git.push_target then
    local push_target
    local text = utils.get_git_icon(git.remote.url) .. git.push_target.name
    if git.push_target.ahead + git.push_target.behind > 0 then
      push_target = {
        NuiText(text, "Fugit2Heading"),
        NuiText " ",
        NuiText(utils.get_ahead_behind_text(git.push_target.ahead, git.push_target.behind), "Fugit2Count"),
      }
    else
      push_target = { NuiText(text, "Fugit2Staged") }
    end
    menu_items[2].texts = push_target
  end

  if git.upstream then
    local upstream_target
    local text = utils.get_git_icon(git.upstream.remote_url) .. git.upstream.name
    if git.upstream.ahead + git.upstream.behind > 0 then
      upstream_target = {
        NuiText(text, "Fugit2Heading"),
        NuiText " ",
        NuiText(utils.get_ahead_behind_text(git.upstream.ahead, git.upstream.behind), "Fugit2Count"),
      }
    else
      upstream_target = { NuiText(text, "Fugit2Staged") }
    end
    local item = { texts = upstream_target, key = "u" }
    table.insert(menu_items, 3, item)
  end

  return menu_items
end

---Menu creation factory.
---@param menu_type Fugit2GitStatusMenu menu to init
---@return Fugit2UITransientMenu
function GitStatus:_init_menus(menu_type)
  local menu_items, menu_title, arg_items, config
  local title_hl = "Fugit2FloatTitle"
  local head_hl = "Fugit2MenuHead"
  local states = self._states
  local git = self._git

  if menu_type == Menu.COMMIT then
    config = self:read_config()

    menu_title = NuiText(" Committing ", title_hl)
    menu_items = {
      { texts = { NuiText("  Create ", head_hl) } },
      { texts = { NuiText "  Commit " }, key = "c" },
      { texts = { NuiText("  Edit ", head_hl), NuiText("HEAD ", "Fugit2Header") } },
      { texts = { NuiText "󰦒  Extend" }, key = "e" },
      { texts = { NuiText "󰧭  Reword" }, key = "r" },
      { texts = { NuiText "󰣪  Amend" }, key = "a" },
      { texts = { NuiText(" 󰽜 Edit ", head_hl) } },
      { texts = { NuiText "󰇾  Fixup" }, key = "f" },
      { texts = { NuiText "󰶯  Squash" }, key = "s" },
      { texts = { NuiText "  Absorb" }, key = "b" },
      { texts = { NuiText("  Log ", head_hl) } },
      { texts = { NuiText "󱁉  Graph" }, key = "g" },
    }
    arg_items = {
      {
        text = NuiText "GPG sign commit",
        key = "-S",
        arg = "--gpg-sign",
        type = UI.INPUT_TYPE.CHECKBOX,
        model = "args",
        default = config and config:get_bool "commit.gpgsign",
      },
    }
  elseif menu_type == Menu.DIFF then
    menu_title = NuiText(" Diffing ", title_hl)
    menu_items = {
      { texts = { NuiText "Diffview" }, key = "d" },
    }
  elseif menu_type == Menu.BRANCH then
    menu_title = NuiText(" Branching ", title_hl)
    menu_items = {
      { texts = { NuiText(" 󱀱 Checkout ", head_hl) } },
      { texts = { NuiText "Branch/Revision" }, key = "b" },
      { texts = { NuiText "Local" }, key = "l" },
      { texts = { NuiText "New branch" }, key = "c" },
      { texts = { NuiText("  Create ", head_hl) } },
      { texts = { NuiText "New branch" }, key = "n" },
    }
    --   NuiMenu.separator(NuiText("Checkout", head_hl), menu_item_align),
    --   NuiMenu.item(NuiLine { NuiText("b ", key_hl), NuiText("Branch/revision") }, { id = "b" }),
    --   NuiMenu.item(NuiLine { NuiText("c ", key_hl), NuiText("New branch") }, { id = "c" }),
    --   NuiMenu.item(NuiLine { NuiText("s ", key_hl), NuiText("New spin-out") }, { id = "s" }),
    --   NuiMenu.separator(NuiText("Create", head_hl), menu_item_align),
    --   NuiMenu.item(NuiLine { NuiText("n ", key_hl), NuiText("New branch") }, { id = "n" }),
    --   NuiMenu.item(NuiLine { NuiText("S ", key_hl), NuiText("New spin-out") }, { id = "S" }),
    --   NuiMenu.separator(NuiText("Do", head_hl), menu_item_align),
    --   NuiMenu.item(NuiLine { NuiText("m ", key_hl), NuiText("Rename") }, { id = "m" }),
    --   NuiMenu.item(NuiLine { NuiText("x ", key_hl), NuiText("Reset") }, { id = "x" }),
    --   NuiMenu.item(NuiLine { NuiText("d ", key_hl), NuiText("Delete") }, { id = "d" }),
    -- }
  elseif menu_type == Menu.PUSH then
    menu_title = NuiText("  Pushing ", title_hl)
    arg_items = {
      {
        text = NuiText "Force with lease",
        key = "-f",
        arg = "--force-with-lease",
        type = UI.INPUT_TYPE.RADIO,
        model = "force",
      },
      {
        text = NuiText "Force",
        key = "-F",
        arg = "--force",
        type = UI.INPUT_TYPE.RADIO,
        model = "force",
      },
    }
    menu_items = {
      { texts = { NuiText("  Push ", head_hl), states.current_text, NuiText(" to ", head_hl) } },
      { texts = { NuiText "@pushRemote" }, key = "p" },
    }
    menu_items = prepare_pull_push_items(git, menu_items)
  elseif menu_type == Menu.FETCH then
    menu_title = NuiText("  Fetching ", title_hl)
    arg_items = {
      {
        text = NuiText "Prune deleted branches",
        key = "-p",
        arg = "--prune",
        type = UI.INPUT_TYPE.CHECKBOX,
        model = "args",
      },
      {
        text = NuiText "Fetch all tags",
        key = "-t",
        arg = "--tags",
        type = UI.INPUT_TYPE.CHECKBOX,
        model = "args",
      },
    }
    menu_items = {
      { texts = { NuiText("  Fetch from ", head_hl) } },
      { texts = { NuiText "@pushRemote" }, key = "p" },
    }

    if git.remote then
      local text = utils.get_git_icon(git.remote.url) .. git.remote.name
      menu_items[2].texts = { NuiText(text, "Fugit2Heading") }
    end

    if git.upstream then
      local text = utils.get_git_icon(git.upstream.remote_url) .. git.upstream.remote
      local item = { texts = { NuiText(text, "Fugit2Heading") }, key = "u" }
      table.insert(menu_items, 3, item)
    end
  elseif menu_type == Menu.PULL then
    menu_title = NuiText("  Pulling ", title_hl)
    arg_items = {
      {
        text = NuiText "Fast-forward only",
        key = "-f",
        arg = "--ff-only",
        type = UI.INPUT_TYPE.CHECKBOX,
        model = "args",
      },
      {
        text = NuiText "Rebase local commits",
        key = "-r",
        arg = "--rebase",
        type = UI.INPUT_TYPE.CHECKBOX,
        model = "args",
      },
      {
        text = NuiText "Autostash",
        key = "-a",
        arg = "autostash",
        type = UI.INPUT_TYPE.CHECKBOX,
        model = "args",
      },
      {
        text = NuiText "Fetch all tags",
        key = "-t",
        arg = "--tags",
        type = UI.INPUT_TYPE.CHECKBOX,
        model = "args",
      },
    }
    menu_items = {
      { texts = { NuiText("  Pull into ", head_hl), states.current_text, NuiText(" from ", head_hl) } },
      { texts = { NuiText "@pushRemote" }, key = "p" },
    }
    menu_items = prepare_pull_push_items(git, menu_items)
  elseif menu_type == Menu.FORGE then
    menu_title = NuiText("  Forge ", title_hl)
    menu_items = {
      { texts = { NuiText(" List ", head_hl) } },
      { texts = { NuiText "Issues" }, key = "li" },
      { texts = { NuiText "Pull Request" }, key = "lp" },
      { texts = { NuiText(" Create ", head_hl) } },
      { texts = { NuiText "Pull Request" }, key = "cp" },
    }
  end

  return UI.Menu(self.ns_id, menu_title, menu_items, arg_items)
end

---Inits Patch View popup
function GitStatus:_init_patch_views()
  local PatchView = require "fugit2.view.components.patch_view"

  local patch_unstaged = PatchView(self.ns_id, "Unstaged", "Fugit2Unstaged")
  local patch_staged = PatchView(self.ns_id, "Staged", "Fugit2Staged")
  local opts = { noremap = true, nowait = true }
  local states = self._states
  local tree = self._views.files
  self._views.patch_unstaged = patch_unstaged
  self._views.patch_staged = patch_staged

  local exit_fn = function()
    self:focus_file()
    vim.api.nvim_feedkeys("q", "m", true)
  end
  patch_unstaged:map("n", { "q", "<esc" }, exit_fn, opts)
  patch_staged:map("n", { "q", "<esc>" }, exit_fn, opts)

  self._prompts.discard_hunk_confirm = UI.Confirm(self.ns_id, NuiLine { NuiText "󰮈 Discard this hunk?" })
  self._prompts.discard_line_confirm = UI.Confirm(self.ns_id, NuiLine { NuiText "󰮈 Discard these lines?" })

  -- Commit menu
  local commit_menu_handler = self:_menu_handlers(Menu.COMMIT)
  patch_unstaged:map("n", "c", commit_menu_handler, opts)
  patch_staged:map("n", "c", commit_menu_handler, opts)

  -- Diff menu
  -- local diff_menu_handler = self:_menu_handlers(Menu.DIFF)
  -- patch_unstaged:map("n", "d", diff_menu_handler, opts)
  -- patch_staged:map("n", "d", diff_menu_handler, opts)

  -- Branch menu
  local branch_menu_handler = self:_menu_handlers(Menu.BRANCH)
  patch_unstaged:map("n", "b", branch_menu_handler, opts)
  patch_staged:map("n", "b", branch_menu_handler, opts)

  -- [h]: move left
  patch_unstaged:map("n", "h", function()
    self:focus_file()
  end, opts)
  patch_staged:map("n", "h", function()
    if states.patch_unstaged_shown then
      patch_unstaged:focus()
    else
      self:focus_file()
    end
  end, opts)

  -- [l]: move right
  patch_unstaged.popup:map("n", "l", function()
    if states.patch_staged_shown then
      patch_staged:focus()
    else
      vim.cmd "normal! l"
    end
  end, opts)

  -- [=]: turn off
  local turn_off_patch_fn = function()
    self:focus_file()
    vim.api.nvim_feedkeys("=", "m", true)
  end
  patch_unstaged:map("n", "=", turn_off_patch_fn, opts)
  patch_staged:map("n", "=", turn_off_patch_fn, opts)

  local diff_apply_fn = function(diff_str, is_index)
    local diff, err = git2.Diff.from_buffer(diff_str)
    if not diff then
      notifier.error("Failed to construct git2 diff", err)
      return -1
    end

    if is_index then
      err = self.repo:apply_index(diff)
    else
      err = self.repo:apply_workdir(diff)
    end
    if err ~= 0 then
      notifier.error("Failed to apply partial diff", err)
      return err
    end
    return 0
  end

  -- updates node status in file tree
  local diff_update_fn = function(node)
    local wstatus, istatus = node.wstatus, node.istatus
    tree:update_single_node(self.repo, node)
    if wstatus ~= node.wstatus or istatus ~= node.istatus then
      tree:render()
    end

    -- invalidate cache
    self._git.unstaged_diff[node.id] = nil
    self._git.staged_diff[node.id] = nil
    -- local unstaged_shown, staged_shown = states.patch_unstaged_shown, states.patch_staged_shown
    states.patch_unstaged_shown, states.patch_staged_shown = self:update_patch(node)
    if states.patch_unstaged_shown or states.patch_staged_shown then
      self:show_patch_view(states.patch_unstaged_shown, states.patch_staged_shown)
    end
    if not states.patch_unstaged_shown and not states.patch_staged_shown then
      -- no more diff in both
      self:focus_file()
    elseif not states.patch_unstaged_shown and states.patch_staged_shown then
      -- no more diff in unstaged
      patch_staged:focus()
    elseif states.patch_unstaged_shown and not states.patch_staged_shown then
      -- no more diff in staged
      patch_unstaged:focus()
    end
  end

  -- [-]/[s]: Stage handling
  patch_unstaged:map("n", { "-", "s" }, function()
    local diff_str = patch_unstaged:get_diff_hunk()
    if not diff_str then
      notifier.error "Failed to get hunk"
      return
    end

    if diff_apply_fn(diff_str, true) == 0 then
      local node, _ = tree:get_child_node_linenr()
      if node then
        diff_update_fn(node)
      end
    end
  end, opts)

  -- [x]/[d]: Discard handling
  self._prompts.discard_hunk_confirm:on_yes(function()
    local diff_str = patch_unstaged:get_diff_hunk_reversed()
    if not diff_str then
      notifier.error "Failed to get hunk"
      return
    end

    if diff_apply_fn(diff_str, false) == 0 then
      local node, _ = tree:get_child_node_linenr()
      if node then
        diff_update_fn(node)
        if node.loaded then
          vim.cmd.checktime(node.id)
        end
      end
    end
  end)
  patch_unstaged:map("n", { "d", "x" }, function()
    self._prompts.discard_hunk_confirm:show()
  end, opts)

  -- [-]/[u]: Unstage handling
  patch_staged:map("n", { "-", "u" }, function()
    local node, _ = tree:get_child_node_linenr()
    if not node then
      return
    end

    local err = 0
    if node.istatus == "A" then
      err = self.repo:reset_default { node.id }
    else
      local diff_str = patch_staged:get_diff_hunk_reversed()
      if not diff_str then
        notifier.error "Failed to get revere hunk"
        return
      end
      err = diff_apply_fn(diff_str, true)
    end

    if err == 0 then
      diff_update_fn(node)
    end
  end, opts)

  -- [-]/[s]: Visual selected staging
  patch_unstaged:map("v", { "-", "s" }, function()
    local cursor_start = vim.fn.getpos("v")[2]
    local cursor_end = vim.fn.getpos(".")[2]

    local diff_str = patch_unstaged:get_diff_hunk_range(cursor_start, cursor_end)
    if not diff_str then
      -- do nothing
      return
    end

    vim.api.nvim_feedkeys(utils.KEY_ESC, "n", false)

    if diff_apply_fn(diff_str, true) == 0 then
      local node, _ = tree:get_child_node_linenr()
      if node then
        diff_update_fn(node)
      end
    end
  end, opts)

  -- [-]/[u]: Visual selected unstage
  patch_staged:map("v", { "-", "u" }, function()
    local cursor_start = vim.fn.getpos("v")[2]
    local cursor_end = vim.fn.getpos(".")[2]

    local diff_str = patch_staged:get_diff_hunk_range_reversed(cursor_start, cursor_end)
    if not diff_str then
      -- do nothing
      return
    end

    vim.api.nvim_feedkeys(utils.KEY_ESC, "n", false)

    if diff_apply_fn(diff_str, true) == 0 then
      local node, _ = tree:get_child_node_linenr()
      if node then
        diff_update_fn(node)
      end
    end
  end, opts)

  -- [d]/[x]: Visual selected discard
  self._prompts.discard_line_confirm:on_yes(function()
    local cursor_start = vim.fn.getpos("v")[2]
    local cursor_end = vim.fn.getpos(".")[2]

    local diff_str = patch_unstaged:get_diff_hunk_range_reversed(cursor_start, cursor_end)
    if not diff_str then
      return
    end

    vim.api.nvim_feedkeys(utils.KEY_ESC, "n", false)

    if diff_apply_fn(diff_str, false) == 0 then
      local node, _ = tree:get_child_node_linenr()
      if node then
        diff_update_fn(node)
        if node.loaded then
          vim.cmd.checktime(node.id)
        end
      end
    end
  end)
  patch_unstaged:map("v", { "d", "x" }, function()
    self._prompts.discard_line_confirm:show()
  end, opts)

  -- Enter to jump to file
  local jump_file_fn = function(v)
    local node, _ = tree:get_child_node_linenr()
    local linenr = v:get_file_line()
    if node then
      self:unmount()
      open_file(self._git.path, node.id, linenr)
    end
  end
  patch_unstaged:map("n", "<cr>", function()
    jump_file_fn(patch_unstaged)
  end, opts)
  patch_staged:map("n", "<cr>", function()
    jump_file_fn(patch_staged)
  end, opts)
end

-- Read git config
---@return GitConfig?
function GitStatus:read_config()
  if self._git.config then
    return self._git.config
  end

  local config, err = self.repo:config()
  if not config then
    notifier.error("Failed to read config", err)
    return nil
  end

  self._git.config = config
  return config
end

-- Read gpg config use_ssh and keyid
---@return Fugit2GitGPGConfig
function GitStatus:read_gpg_config()
  local config = self:read_config()
  if not config then
    return { use_ssh = false }
  end

  local keyid = config:get_string "user.signingkey" or nil
  local use_ssh = (config:get_string "gpg.format" == "ssh")

  if not use_ssh and self._git.signature then
    -- get committer info as key id
    keyid = tostring(self._git.signature)
  end

  return {
    use_ssh = use_ssh,
    keyid = keyid,
    program = config:get_string "gpg.ssh.program" or nil,
  }
end

-- Updates git status.
---@param callback fun()?
function GitStatus:update(callback)
  utils.list_clear(self._status_lines)
  -- clean cached menus
  self._menus[Menu.PUSH] = nil
  self._menus[Menu.PULL] = nil
  -- clean cached diffs
  if self._git.unstaged_diff then
    utils.table_clear(self._git.unstaged_diff)
  end
  if self._git.staged_diff then
    utils.table_clear(self._git.staged_diff)
  end

  local status_head, status_upstream, diff_head_to_index, err
  ---@type NuiLine[]
  local lines = self._status_lines

  status_head, status_upstream, err = self.repo:status_head_upstream()
  if not status_head then
    local line = NuiLine { NuiText("HEAD  ", "Fugit2Header") }

    -- Get status head only
    local head, _ = self.repo:reference_lookup "HEAD"
    local head_ref_name = head and head:symbolic_target()
    if head_ref_name then
      local head_namespace = git2.reference_name_namespace(head_ref_name)
      local head_icon = utils.get_git_namespace_icon(head_namespace)
      local head_name = git2.reference_name_shorthand(head_ref_name)
      line:append(head_icon .. head_name .. "  ", "Fugit2BranchHead")
    end

    if err == git2.GIT_ERROR.GIT_EUNBORNBRANCH then
      line:append("No commits!", "Error")
    elseif err == git2.GIT_ERROR.GIT_EUNBORNBRANCH then
      line:append("Non existing branch!", "Error")
    elseif err == git2.GIT_ERROR.GIT_ENOTFOUND then
      line:append("Missing!", "Error")
    else
      line:append("Libgit2 code: " .. err, "Error")
    end
    lines[1] = line

    -- render top head
    vim.schedule(function()
      self:render_top_info()
    end)
  else
    -- update status panel
    self._git.head = status_head

    local remote, _ = self.repo:remote_default()
    if remote then
      self._git.remote = {
        name = remote.name,
        url = remote.url,
        push_url = remote.push_url,
      }
    end

    if not self._git.remote_icons then
      local remote_icons = {}
      local remotes = self.repo:remote_list()
      if remotes then
        for _, r in ipairs(remotes) do
          local rem, _ = self.repo:remote_lookup(r)
          remote_icons[r] = rem and utils.get_git_icon(rem.url) or nil
        end
      end
      self._git.remote_icons = remote_icons
    end

    local head_line = NuiLine { NuiText("HEAD", "Fugit2Header") }
    if status_head.is_detached then
      head_line:append(" (detached)", "Fugit2Heading")
    else
      head_line:append "     "
    end

    local ahead, behind = 0, 0
    if status_upstream then
      ahead, behind = status_upstream.ahead, status_upstream.behind
      self._git.ahead, self._git.behind = ahead, behind
      self._git.upstream = status_upstream
    end
    local ahead_behind = ahead + behind

    local branch_width = math.max(
      status_head.name:len() + (ahead_behind > 0 and 5 or 0),
      status_upstream and status_upstream.name:len() or 0
    )
    local branch_format = "%s%-" .. branch_width .. "s"

    local author_width = math.max(status_head.author:len(), status_upstream and status_upstream.author:len() or 0)
    local author_format = " %-" .. author_width .. "s"

    local head_icon = utils.get_git_namespace_icon(status_head.namespace)

    self._states.current_text = NuiText(head_icon .. status_head.name, "Fugit2BranchHead")

    if ahead_behind == 0 then
      head_line:append(string.format(branch_format, head_icon, status_head.name), "Fugit2BranchHead")
    else
      head_line:append(head_icon .. status_head.name, "Fugit2BranchHead")
      local padding = (branch_width - status_head.name:len() - (ahead > 0 and 2 or 0) - (behind > 0 and 2 or 0))
      if padding > 0 then
        head_line:append(string.rep(" ", padding))
      end
      local ahead_behind_str = utils.get_ahead_behind_text(ahead, behind)

      head_line:append(ahead_behind_str, "Fugit2Count")
    end

    head_line:append(string.format(author_format, status_head.author), "Fugit2Author")
    head_line:append(string.format(" %s ", status_head.oid), "Fugit2ObjectId")
    head_line:append(utils.message_title_prettify(status_head.message))
    table.insert(lines, head_line)

    local upstream_line = NuiLine { NuiText("Upstream ", "Fugit2Header") }
    if status_upstream then
      self._prompts.amend_confirm:set_text(NuiLine {
        NuiText "This commit has already been pushed to ",
        NuiText(status_upstream.name, "Fugit2SymbolicRef"),
        NuiText ", do you really want to modify it?",
      })

      local remote_icon = utils.get_git_icon(status_upstream.remote_url)

      local upstream_name = string.format(branch_format, remote_icon, status_upstream.name)
      local upstream_text
      if status_upstream.ahead > 0 or status_upstream.behind > 0 then
        upstream_text = NuiText(upstream_name, "Fugit2Heading")
      else
        upstream_text = NuiText(upstream_name, "Fugit2Staged")
      end
      upstream_line:append(upstream_text)
      self._states.upstream_text = upstream_text

      upstream_line:append(string.format(author_format, status_upstream.author), "Fugit2Author")
      upstream_line:append(string.format(" %s ", status_upstream.oid), "Fugit2ObjectId")

      upstream_line:append(utils.message_title_prettify(status_upstream.message))
    else
      upstream_line:append("?", "Fugit2SymbolicRef")
    end
    table.insert(lines, upstream_line)

    -- get info of default push
    if status_head.namespace == git2.GIT_REFERENCE_NAMESPACE.BRANCH then
      local push_remote = self.repo:branch_push_remote(status_head.name)
      if push_remote then
        local push_name = push_remote .. "/" .. status_head.name
        local push_ref = "refs/remotes/" .. push_name

        if status_upstream and push_name == status_upstream.name then
          self._git.push_target = {
            name = push_name,
            oid = status_upstream.oid and tostring(status_upstream.oid) or "",
            ahead = status_upstream.ahead,
            behind = status_upstream.behind,
          }
        else
          local push_target_id, _ = self.repo:reference_name_to_id(push_ref)
          if push_target_id and status_head.oid then
            local ahead1, behind1 = self.repo:ahead_behind(status_head.oid, push_target_id)
            self._git.push_target = {
              name = push_name,
              oid = tostring(push_target_id),
              ahead = ahead1 or 0,
              behind = behind1 or 0,
            }
          end
        end
      end
    end

    -- render top head
    vim.schedule(function()
      self:render_top_info()
    end)

    -- update branches tree
    -- local branches, err = self.repo:branches(true, false)
    -- if not branches then
    --   vim.notify("[Fugit2] Failed to get local branch list, error code: " .. err)
    -- else
    --   self._branches_view:update(branches, git_status.head.refname)
    -- end

    -- update top commits graph
    if self._git.walker then
      local id_len = 16
      self._git.walker:reset()

      if status_upstream then
        self._git.walker:push(status_upstream.oid)
      end

      self._git.walker:push(status_head.oid)

      local commits = {}
      for oid, commit in self._git.walker:iter() do
        local parents = vim.tbl_map(function(p)
          return p:tostring(id_len)
        end, commit:parent_oids())

        local id_str = oid:tostring(id_len)
        local refs = {}
        if oid == status_head.oid then
          refs[1] = status_head.refname
        end
        if status_upstream and oid == status_upstream.oid then
          refs[#refs + 1] = "refs/remotes/" .. status_upstream.name
        end

        commits[#commits + 1] =
          LogView.CommitNode(id_str, commit:summary(), commit:author(), commit:time(), parents, refs)

        if #commits > GIT_LOG_MAX_COMMITS then
          break
        end
      end

      local commit_view = self._views.commits
      commit_view:update(commits, self._git.remote_icons)

      -- render bottom pane
      vim.schedule(function()
        commit_view:render()
      end)
    end
  end

  self.repo:status_async(function(status_items, e)
    if status_items then
      diff_head_to_index = self.repo:diff_head_to_index(self.index)
      -- update files tree
      vim.schedule(function()
        self._views.files:update(status_items, self._git.path, diff_head_to_index)
        if callback then
          callback()
        end
      end)
    end
  end)
end

function GitStatus:update_then_render()
  self:update(function()
    self:render()

    if self._states.side_panel == SidePanel.PATCH_VIEW then
      self._states.last_patch_line = -1
      self:show_patch_for_current_file()
    end
  end)
end

function GitStatus:render_top_info()
  local bufnr = self.info_popup.bufnr
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(bufnr, "readonly", false)

  for i, line in ipairs(self._status_lines) do
    line:render(self.info_popup.bufnr, self.ns_id, i)
  end

  vim.api.nvim_buf_set_option(bufnr, "readonly", true)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

-- Renders git status only
function GitStatus:render()
  -- self:render_top_info()
  self._views.files:render()
  -- self._views.commits:render()
end

-- Scrolls to active file
function GitStatus:scroll_to_active_file()
  local current_file = self._states.current_file
  local _, linenr = self._views.files.tree:get_node("-" .. current_file)
  if linenr then
    vim.schedule(function()
      vim.api.nvim_win_set_cursor(0, { linenr, 1 })
    end)
  end
end

-- Shows patch view for current file
function GitStatus:show_patch_for_current_file()
  local file_tree = self._views.files
  local states = self._states

  local node, linenr = file_tree:get_child_node_linenr()
  if node and linenr and linenr ~= states.last_patch_line then
    states.patch_unstaged_shown, states.patch_staged_shown = self:update_patch(node)

    if states.patch_unstaged_shown or states.patch_staged_shown then
      self:show_patch_view(states.patch_unstaged_shown, states.patch_staged_shown)
      states.last_patch_line = linenr
    end
  elseif linenr then
    self:show_patch_view(states.patch_unstaged_shown, states.patch_staged_shown)
  end
end

-- Shows patch for active file
function GitStatus:show_patch_for_active_file()
  local states = self._states
  local active_file = self._states.current_file
  local node, linenr = self._views.files.tree:get_node("-" .. active_file)
  if not linenr then
    node, linenr = self._views.files:get_child_node_linenr()
  end

  if node and linenr and linenr ~= states.last_patch_line then
    states.patch_unstaged_shown, states.patch_staged_shown = self:update_patch(node)
    if states.patch_unstaged_shown or states.patch_staged_shown then
      self:show_patch_view(states.patch_unstaged_shown, states.patch_staged_shown)
      states.last_patch_line = linenr
    end
  end
end

function GitStatus:mount()
  self._layout:mount()
  self:focus_file()
end

---Exit function
function GitStatus:unmount()
  self:write_index()
  self.closed = true

  self._status_lines = nil

  for _, v in ipairs(self._views) do
    v:unmount()
  end
  self._views = nil

  for _, p in ipairs(self._prompts) do
    p:unmount()
  end
  self._prompts = nil

  self._menus = {}
  self.command_popup:unmount()
  if self.input_popup then
    self.input_popup:unmount()
  end
  if self.branch_input then
    self.branch_input:unmount()
  end
  self._layout:unmount()

  vim.api.nvim_set_current_win(self._states.last_window)
end

function GitStatus:write_index()
  if self._git.index_updated then
    if self.index:write() == 0 then
      self._git.index_updated = false
    end
  end
end

---@param node NuiTree.Node
---@overload fun(node: NuiTree.Node)
function GitStatus:_remove_cached_states(node)
  -- remove cached diff
  self._git.staged_diff[node.id] = nil
  self._git.unstaged_diff[node.id] = nil
end

function GitStatus:_refresh_views()
  local tree = self._views.files
  local states = self._states

  -- old node at current cursor maybe deleted after stage/unstage
  local node, linenr = tree:get_child_node_linenr()
  if node and linenr then
    if states.side_panel == SidePanel.NONE then
      states.last_patch_line = -1 -- remove cache behaviors
    elseif states.side_panel == SidePanel.PATCH_VIEW then
      states.patch_unstaged_shown, states.patch_staged_shown = self:update_patch(node)
      if states.patch_unstaged_shown or states.patch_staged_shown then
        self:show_patch_view(states.patch_unstaged_shown, states.patch_staged_shown)
        states.last_patch_line = linenr
      end
    end
  end
end

function GitStatus:focus_input()
  local input_popup = self:get_input_popup()

  self._layout:update(NuiLayout.Box({
    NuiLayout.Box(self.info_popup, { size = 6 }),
    NuiLayout.Box(input_popup, { size = 6 }),
    NuiLayout.Box(self._boxes.main_row, { dir = "row", grow = 1 }),
  }, { dir = "col" }))
  vim.api.nvim_set_current_win(input_popup.winid)
end

function GitStatus:focus_command()
  self._layout:update(NuiLayout.Box({
    NuiLayout.Box(self.info_popup, { size = 6 }),
    NuiLayout.Box(self.command_popup, { size = 6 }),
    NuiLayout.Box(self._views.commits.popup, { grow = 1 }),
  }, { dir = "col" }))
end

function GitStatus:focus_file()
  self._views.files:focus()
end

function GitStatus:focus_branch_input()
  local input = self:get_branch_input()

  self._layout:update(NuiLayout.Box({
    NuiLayout.Box(self.info_popup, { size = 6 }),
    NuiLayout.Box(input, { size = 3 }),
    NuiLayout.Box(self._boxes.main_row, { dir = "row", grow = 1 }),
  }, { dir = "col" }))
end

-- Creates branch from ref
---@param ref string reference name to create from
---@param checkout boolean checkout new branch
function GitStatus:create_branch(ref, checkout)
  local mode = checkout and BranchMode.CREATE_CHECKOUT or BranchMode.CREATE

  self._states.branch_mode = mode
  self._states.branch_ref = ref

  local title = NuiLine()
  title:append(checkout and " Create and checkout branch from " or " Create branch from ", "Fugit2MessageHeading")
  title:append(git2.reference_name_shorthand(ref) .. " ", "Fugit2BranchHead")

  self:get_branch_input().border:set_text("top", title, "left")

  self:focus_branch_input()
  vim.cmd.startinsert()
end

---Hides input popup
---@param reset_to_main boolean Reset back to main layout
function GitStatus:hide_input(reset_to_main)
  if self.input_popup then
    vim.api.nvim_buf_set_lines(self.input_popup.bufnr, 0, -1, true, {})
  end

  if self.branch_input then
    vim.api.nvim_buf_set_lines(self.branch_input.bufnr, -2, -1, true, { "" })
  end

  local layout = self._layout

  if reset_to_main or self._states.side_panel == SidePanel.NONE then
    self._states.side_panel = SidePanel.NONE
    layout:update(self._layout_opts.main, self._boxes.main)
  else
    local boxes = vim.list_slice(layout._.box.box)

    if #boxes > 1 then
      table.remove(boxes, 2)
      layout:update(NuiLayout.Box(boxes, { dir = "col" }))
    end
  end

  self:focus_file()
end

function GitStatus:insert_head_message_to_input()
  vim.api.nvim_buf_set_lines(
    self.input_popup.bufnr,
    0,
    -1,
    true,
    vim.split(self._git.head.message, "\n", { plain = true, trimempty = true })
  )
end

---@param signature GitSignature
---@param message string
---@return string? prettified
local function check_signature_message(signature, message)
  if not signature then
    notifier.error "No default author"
    return nil
  end

  if message == "" then
    notifier.error "Empty commit message"
    return nil
  end

  local prettified, err = git2.message_prettify(message)
  if err ~= 0 then
    notifier.error "Failed to clean message"
    return nil
  end

  return prettified
end

-- Creates a commit
---@param message string
---@param args string[]?
function GitStatus:_git_create_commit(message, args)
  local gpg_sign = args and vim.tbl_contains(args, "--gpg-sign")
  local prettified = check_signature_message(self._git.signature, message)

  if not self._git.signature then
    notifier.error "Can not find git signature!"
    return
  end

  if not prettified then
    notifier.error "Can not prettify commit message!"
    return
  end

  local result = {}

  async.run(
    -- async fun, create index
    function()
      -- save index before creating commit
      self:write_index()

      local commit_id, err
      if not gpg_sign then
        commit_id, err = self.repo:create_commit(self.index, self._git.signature, prettified)
        result.commit_id = commit_id
        result.err = err
      else
        -- create commit with gpg sign
        local conf = self:read_gpg_config()
        local err_msg
        commit_id, err, err_msg =
          git_gpg.create_commit_gpg(self.repo, self.index, self._git.signature, prettified, conf)
        result.commit_id = commit_id
        result.err = err
        result.message = err_msg
      end
    end,

    -- callback func, called when finished
    async_utils.scheduler(function()
      if result.commit_id then
        notifier.info(string.format("New %scommit %s", gpg_sign and "signed " or "", result.commit_id:tostring(8)))
        self:hide_input(false)
        self:update_then_render()
      else
        notifier.error(result.message or "Failed creating commit", result.err or 0)
      end
    end)
  )
end

---Extends HEAD commit
---add files in index to HEAD commit
---@param args string[]?
function GitStatus:_git_extend_commit(args)
  local gpg_sign = args and vim.tbl_contains(args, "--gpg-sign")

  self:write_index()

  local commit_id, err, err_msg
  if not gpg_sign then
    commit_id, err = self.repo:amend_extend(self.index)
  else
    -- extend commit with gpg sign
    local conf = self:read_gpg_config()
    commit_id, err, err_msg = git_gpg.extend_commit_gpg(self.repo, self.index, conf)
  end

  if commit_id then
    notifier.info("Extend HEAD " .. commit_id:tostring(8))
    self:update_then_render()
  else
    err_msg = (err_msg and err_msg ~= "") and err_msg or "Failed to extend HEAD"
    notifier.error(err_msg, err)
  end
end

---Reword HEAD commit
---change commit message of HEAD commit
---@param message string commit message
---@param args string[]?
function GitStatus:_git_reword_commit(message, args)
  local gpg_sign = args and vim.tbl_contains(args, "--gpg-sign")

  local signature = self._git.signature
  if not signature then
    notifier.error "Can not find git signature!"
    return
  end

  local prettified = check_signature_message(signature, message)
  if not prettified then
    notifier.error "Can not prettify commit message!"
    return
  end

  local commit_id, err, err_msg
  if not gpg_sign then
    commit_id, err = self.repo:amend_reword(signature, prettified)
  else
    -- reword commit with gpg sign
    local conf = self:read_gpg_config()
    commit_id, err, err_msg = git_gpg.reword_commit_gpg(self.repo, signature, prettified, conf)
  end

  if commit_id then
    notifier.info("Reword HEAD " .. commit_id:tostring(8))
    self:hide_input(false)
    self:update_then_render()
  else
    err_msg = (err_msg and err_msg ~= "") and err_msg or "Failed to reword HEAD"
    notifier.error(err_msg, err)
  end
end

---Amend HEAD commit
---add files from index and also change message or HEAD commit
---@param message string
---@param args string[]?
function GitStatus:_git_amend_commit(message, args)
  local gpg_sign = args and vim.tbl_contains(args, "--gpg-sign")

  local signature = self._git.signature
  if not signature then
    notifier.error "Can not find git signature!"
    return
  end

  local prettified = check_signature_message(signature, message)
  if not prettified then
    notifier.error "Can not prettify commit message!"
    return
  end

  self:write_index()

  local commit_id, err, err_msg
  if not gpg_sign then
    commit_id, err = self.repo:amend(self.index, self._git.signature, prettified)
  else
    local conf = self:read_gpg_config()
    commit_id, err, err_msg = git_gpg.amend_commit_gpg(self.repo, self.index, signature, prettified, conf)
  end

  if commit_id then
    notifier.info("Amend HEAD " .. commit_id:tostring(8))
    self:hide_input(false)
    self:update_then_render()
  else
    err_msg = (err_msg and err_msg ~= "") and err_msg or "Failed to amend HEAD"
    notifier.error(err_msg, err)
  end
end

---@param init_str string
---@param include_changes boolean
---@param notify_empty boolean
function GitStatus:_set_input_popup_commit_title(init_str, include_changes, notify_empty)
  local file_changed, insertions, deletions = 0, 0, 0
  if include_changes then
    local diff, _ = self.repo:diff_head_to_index(self.index, nil, false)
    if diff then
      local stats, _ = diff:stats()
      if stats then
        file_changed = stats.changed
        insertions = stats.insertions
        deletions = stats.deletions
      end
    end
    if notify_empty and file_changed + insertions + deletions < 1 then
      notifier.warn "Empty commit!"
    end
  end

  local title = string.format(
    " %s -  %s %s%s%s",
    init_str,
    tostring(self._git.signature),
    file_changed > 0 and string.format("%d 󰈙", file_changed) or "",
    insertions > 0 and string.format(" +%d", insertions) or "",
    deletions > 0 and string.format(" -%d", deletions) or ""
  )

  self:get_input_popup().border:set_text("top", NuiText(title, "Fugit2MessageHeading"), "left")
end

---@param args string[]
function GitStatus:commit_create(args)
  self._states.commit_mode = CommitMode.CREATE
  self._states.commit_args = args

  self:_set_input_popup_commit_title("Create commit", true, true)

  self:focus_input()
  vim.cmd.startinsert()
end

---@param args string[]
function GitStatus:commit_extend(args)
  self._states.commit_mode = CommitMode.EXTEND

  if self._git.ahead == 0 then
    self._states.commit_args = args
    self._prompts.amend_confirm:show()
  else
    self:_git_extend_commit(args)
  end
end

---@param is_reword boolean reword only mode
---@param args string[]
function GitStatus:commit_amend(is_reword, args)
  self._states.commit_mode = is_reword and CommitMode.REWORD or CommitMode.AMEND
  self._states.commit_args = args

  if self._git.ahead == 0 then
    self._prompts.amend_confirm:show()
    return
  end

  if is_reword then
    self:_set_input_popup_commit_title("Reword HEAD", false, false)
  else
    self:_set_input_popup_commit_title("Amend HEAD", true, false)
  end

  self:insert_head_message_to_input()
  self:focus_input()
end

function GitStatus:amend_confirm_yes_handler()
  return function()
    local mode = self._states.commit_mode
    if mode == CommitMode.EXTEND then
      self:_git_extend_commit(self._states.commit_args)
    elseif mode == CommitMode.REWORD or mode == CommitMode.AMEND then
      if mode == CommitMode.REWORD then
        self:_set_input_popup_commit_title("Reword HEAD", false, false)
      else
        self:_set_input_popup_commit_title("Amend HEAD", true, false)
      end

      self:insert_head_message_to_input()
      self:focus_input()
    end
  end
end

function GitStatus:_init_commit_menu()
  local m = self:_init_menus(Menu.COMMIT)
  m:on_submit(function(item_id, args)
    if item_id == "c" then
      self:commit_create(args["args"])
    elseif item_id == "e" then
      self:commit_extend(args["args"])
    elseif item_id == "r" then
      self:commit_amend(true, args["args"])
    elseif item_id == "a" then
      self:commit_amend(false, args["args"])
    elseif item_id == "g" then
      self._menus[Menu.COMMIT]:unmount()
      self:unmount()
      require("fugit2.view.ui").new_fugit2_graph_window(self.ns_id, self.repo):mount()
    end
  end)
  return m
end

---Updates patch info based on node
---@param node NuiTree.Node
---@return boolean unstaged_updated
---@return boolean staged_updated
function GitStatus:update_patch(node)
  local unstaged_updated, staged_updated = false, false

  -- init in the first update
  if not self._views.patch_staged or not self._views.patch_unstaged then
    self:_init_patch_views()
  end

  if node.id then
    local diff, patches, err, found
    local paths = { node.id, node.alt_path }

    found = self._git.unstaged_diff[node.id]
    if node.wstatus ~= "-" and not found then
      diff, err = self.repo:diff_index_to_workdir(self.index, paths)
      if not diff then
        notifier.error("Failed to get unstaged diff", err)
        goto git_status_update_patch_index
      end
      patches, err = diff:patches(false)
      if #patches == 0 then
        notifier.error("Failed to get unstaged patch", err)
        goto git_status_update_patch_index
      end
      self._git.unstaged_diff[node.id] = patches[1]
      found = patches[1]
    end

    if found then
      self._views.patch_unstaged:update(found)
      unstaged_updated = true
    end

    ::git_status_update_patch_index::
    found = self._git.staged_diff[node.id]
    if node.istatus ~= "-" and node.istatus ~= "?" and not found then
      diff, err = self.repo:diff_head_to_index(self.index, paths)
      if not diff then
        notifier.error("Failed to get staged diff", err)
        goto git_status_update_patch_end
      end
      patches, err = diff:patches(false)
      if #patches == 0 then
        notifier.error("Failed to get staged patch", err)
        goto git_status_update_patch_end
      end
      self._git.staged_diff[node.id] = patches[1]
      found = patches[1]
    end

    if found then
      self._views.patch_staged:update(found)
      staged_updated = true
    end
  end

  ::git_status_update_patch_end::
  return unstaged_updated, staged_updated
end

---@param unstaged boolean show unstaged diff
---@param staged boolean show staged diff
function GitStatus:show_patch_view(unstaged, staged)
  if not unstaged and not staged then
    return
  end

  local row
  if unstaged and staged then
    row = self._boxes.patch_unstaged_staged
    if not row then
      row = utils.update_table(self._boxes, "patch_unstaged_staged", {
        NuiLayout.Box(self._views.files.popup, { size = self.opts.min_width }),
        NuiLayout.Box(self._views.patch_unstaged.popup, { grow = 1 }),
        NuiLayout.Box(self._views.patch_staged.popup, { grow = 1 }),
      })
    end
  elseif unstaged then
    row = self._boxes.patch_unstaged
    if not row then
      row = utils.update_table(self._boxes, "patch_unstaged", {
        NuiLayout.Box(self._views.files.popup, { size = self.opts.min_width }),
        NuiLayout.Box(self._views.patch_unstaged.popup, { grow = 1 }),
      })
    end
  else
    row = self._boxes.patch_staged
    if not row then
      row = utils.update_table(self._boxes, "patch_staged", {
        NuiLayout.Box(self._views.files.popup, { size = self.opts.min_width }),
        NuiLayout.Box(self._views.patch_staged.popup, { grow = 1 }),
      })
    end
  end

  self._boxes.main_row = row
  self._layout:update(
    self._layout_opts.diff,
    NuiLayout.Box({
      NuiLayout.Box(self.info_popup, { size = 6 }),
      NuiLayout.Box(row, { dir = "row", grow = 1 }),
    }, { dir = "col" })
  )
  self._states.side_panel = SidePanel.PATCH_VIEW

  if self.opts.min_width ~= self._states.file_entry_width then
    self._views.files:set_width(self.opts.min_width)
    self._views.files:render()
  end
end

function GitStatus:hide_patch_view()
  self._layout:update(self._layout_opts.main, self._boxes.main)
  self._boxes.main_row = NuiLayout.Box(self._views.files.popup, { grow = 1 })
  self._states.side_panel = SidePanel.NONE

  if self.opts.min_width ~= self._states.file_entry_width then
    self._views.files:set_width(self._states.file_entry_width)
    self._views.files:render()
  end
end

-- ======================
-- | Commit input popup |
-- ======================

---@return NuiPopup
function GitStatus:_init_input_popup()
  local default_padding = {
    top = 0,
    bottom = 0,
    left = 1,
    right = 1,
  }
  local win_hl = "Normal:Normal,FloatBorder:FloatBorder"

  local input_popup = NuiPopup {
    ns_id = self.ns_id,
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      padding = default_padding,
      text = {
        top = NuiText(" Create commit ", "Fugit2MessageHeading"),
        top_align = "left",
        bottom = NuiText("[Ctrl-c][󱊷 ][q]uit, [Ctrl 󰌑 ][󰌑 ]", "FloatFooter"),
        bottom_align = "right",
      },
    },
    win_options = {
      winhighlight = win_hl,
    },
    buf_options = {
      modifiable = true,
      filetype = "gitcommit",
    },
  }

  vim.api.nvim_buf_set_extmark(input_popup.bufnr, self.ns_id, 0, 0, {
    id = 1,
    end_row = 0,
    virt_text = {
      { "commit message", "Comment" },
    },
    virt_text_pos = "right_align",
    virt_text_hide = true,
  })

  local opts = { noremap = true, nowait = true }
  local states = self._states

  input_popup:map("n", { "q", "<esc>" }, function()
    self:hide_input(false)
  end, opts)

  input_popup:map("i", "<C-c>", "<esc>q", { nowait = true })

  local input_enter_fn = function()
    local message = vim.trim(table.concat(vim.api.nvim_buf_get_lines(self.input_popup.bufnr, 0, -1, true), "\n"))
    if states.commit_mode == CommitMode.CREATE then
      self:_git_create_commit(message, states.commit_args)
    elseif states.commit_mode == CommitMode.REWORD then
      self:_git_reword_commit(message, states.commit_args)
    elseif states.commit_mode == CommitMode.AMEND then
      self:_git_amend_commit(message, states.commit_args)
    end

    states.commit_args = nil
  end
  input_popup:map("n", "<cr>", input_enter_fn, opts)
  input_popup:map("i", "<C-cr>", function()
    vim.cmd.stopinsert()
    input_enter_fn()
  end, opts)

  return input_popup
end

function GitStatus:get_input_popup()
  local input = self.input_popup
  if input then
    return input
  end

  input = self:_init_input_popup()
  self.input_popup = input
  return input
end

-- ======================
-- | Branch input popup |
-- ======================

---@return NuiPopup
function GitStatus:_init_branch_input()
  local default_padding = {
    top = 0,
    bottom = 0,
    left = 1,
    right = 1,
  }
  local win_hl = "Normal:Normal,FloatBorder:FloatBorder"
  local input = NuiPopup {
    ns_id = self.ns_id,
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      padding = default_padding,
      text = {
        top = NuiText(" Create branch ", "Fugit2MessageHeading"),
        top_align = "left",
        bottom = NuiText("[Ctrl-c][󱊷 ][q]uit, [Ctrl 󰌑 ][󰌑 ]", "FloatFooter"),
        bottom_align = "right",
      },
    },
    win_options = {
      winhighlight = win_hl,
    },
    buf_options = {
      modifiable = true,
      buftype = "prompt",
    },
  }

  -- Create branch
  vim.fn.prompt_setprompt(input.bufnr, " ")
  vim.fn.prompt_setcallback(input.bufnr, function(name)
    if name == "" then
      notifier.warn "Emtpy branch name"
      return
    end

    if not self._states.branch_ref then
      notifier.error "Empty branch reference name"
      self:hide_input(false)
      return
    end

    local ref, err = self.repo:reference_lookup(self._states.branch_ref)
    if not ref then
      notifier.error("Fail to look up reference", err)
      self:hide_input(false)
      return
    end

    local commit
    commit, err = ref:peel_commit()
    if not commit then
      notifier.error("Failed to convert reference to commit", err)
      self:hide_input(false)
      return
    end

    ref, err = self.repo:create_branch(name, commit, false)
    if not ref then
      notifier.error("Can't create new branch", err)
      self:hide_input(false)
      return
    end

    if self._states.branch_mode == BranchMode.CREATE_CHECKOUT then
      err = self.repo:checkout(ref.name)
      if err ~= 0 then
        notifier.error("Can't checkout " .. ref.name, err)
      else
        notifier.info("Created and checked out " .. ref:shorthand())
      end
    else
      notifier.info("Created new branch " .. ref:shorthand())
    end

    self:hide_input(true)
    self:update_then_render()
  end)

  local exit_fn = function()
    self:hide_input(false)
  end

  local opts = { nowait = true, noremap = true }

  vim.fn.prompt_setinterrupt(input.bufnr, exit_fn)
  input:map("n", { "<esc>", "q" }, exit_fn, opts)

  return input
end

function GitStatus:get_branch_input()
  local input = self.branch_input
  if input then
    return input
  end

  input = self:_init_branch_input()
  self.branch_input = input
  return input
end

-- ================
-- |  Forge Menu |
-- ===============

function GitStatus:_init_forge_menu()
  local m = self:_init_menus(Menu.FORGE)
  m:on_submit(function(item_id, _)
    if item_id == "cp" then
      require("tinygit").createGitHubPr()
    elseif item_id == "li" then
      require("tinygit").issuesAndPrs { type = "issue", state = "all" }
    elseif item_id == "lp" then
      require("tinygit").issuesAndPrs { type = "pr", state = "all" }
    end
  end)
  return m
end

-- ===============
-- |  Diff Menu  |
-- ===============

---GitStatus Diff Menu
---@return Fugit2UITransientMenu
function GitStatus:_init_diff_menu()
  local m = self:_init_menus(Menu.DIFF)
  m:on_submit(function(item_id, _)
    if item_id == "d" then
      local node, _ = self._views.files:get_child_node_linenr()
      if not node then
        return
      end

      if self.opts.external_diffview and vim.fn.exists ":DiffviewOpen" > 0 then
        self:unmount()
        vim.cmd { cmd = "DiffviewOpen", args = { "--selected-file=" .. vim.fn.fnameescape(node.id) } }
      else
        self:unmount()
        local diffview = (require "fugit2.view.ui").new_fugit2_diff_view(self.ns_id, self.repo)
        diffview:mount()
        diffview:focus_file(vim.fn.fnameescape(node.id))
      end
    end
  end)
  return m
end

---GitStatus Branch Menu
---@return Fugit2UITransientMenu
function GitStatus:_init_branch_menu()
  local m = self:_init_menus(Menu.BRANCH)

  local checkout_fn = function(ref)
    local err = self.repo:checkout(ref)
    if err ~= 0 then
      notifier.error("Failed to checkout " .. git2.reference_name_shorthand(ref), err)
    else
      notifier.info("Checked out " .. git2.reference_name_shorthand(ref))
      self:update_then_render()
    end
    self:focus_file()
  end

  m:on_submit(function(item_id, _)
    local GitPick = require "fugit2.view.git_pick"

    if item_id == "b" then
      local pick_view = GitPick(self.ns_id, self.repo, GitPick.ENTITY.BRANCH_LOCAL_REMOTE, " Checkout branch/revision ")
      pick_view:on_submit(checkout_fn)
      pick_view:mount()
    elseif item_id == "l" then
      local pick_view = GitPick(self.ns_id, self.repo, GitPick.ENTITY.BRANCH_LOCAL, " Checkout branch ")
      pick_view:on_submit(checkout_fn)
      pick_view:mount()
    elseif item_id == "c" then
      local pick_view =
        GitPick(self.ns_id, self.repo, GitPick.ENTITY.BRANCH_LOCAL_REMOTE, " Create and checkout branch from ")
      pick_view:on_submit(function(ref)
        self:create_branch(ref, true)
      end)
      pick_view:mount()
    elseif item_id == "n" then
      local pick_view = GitPick(self.ns_id, self.repo, GitPick.ENTITY.BRANCH_LOCAL_REMOTE, " Create brannch from ")
      pick_view:on_submit(function(ref)
        self:create_branch(ref, false)
      end)
      pick_view:mount()
    end
  end)
  return m
end

---GitStatus Pushing Menu
---@return Fugit2UITransientMenu
function GitStatus:_init_push_menu()
  local m = self:_init_menus(Menu.PUSH)
  m:on_submit(function(item_id, args)
    if item_id == "p" then
      self:push_current_to_pushremote(args["force"])
    elseif item_id == "u" then
      self:push_current_to_upstream(args["force"])
    end
  end)
  return m
end

---@param args string[]
function GitStatus:push_current_to_pushremote(args)
  ---@type string[]
  local git_args = { "push" }
  local git = self._git
  local current = git.head
  local remote = git.remote

  if not git.upstream then
    -- set upstream if there are no upstream
    git_args[#git_args + 1] = "-u"
  end

  if args[1] == "--force" then
    git_args[#git_args + 1] = args[1]
  elseif args[1] == "--force-with-lease" then
    --force with lease
    local lease = args[1]
    if current then
      lease = lease .. "=" .. current.name

      if git.push_target then
        lease = lease .. ":" .. git.push_target.oid
      end
    end
    git_args[#git_args + 1] = lease
  end

  if remote then
    git_args[#git_args + 1] = remote.name
  end
  if current then
    git_args[#git_args + 1] = current.name .. ":" .. current.name
  end

  self:run_command("git", git_args, true)
end

---@param args string[]
function GitStatus:push_current_to_upstream(args)
  ---@type string[]
  local git_args = { "push" }
  local git = self._git
  local current = git.head
  local upstream = git.upstream

  if not current or not upstream then
    error "[Fugit2] Upstream Not Found"
    return
  end

  local split, _ = upstream.name:find("/", 1, true)
  if not split then
    error "[Fugit2] Invalid upstream name"
    return
  end
  local upstream_name = upstream.name:sub(split + 1)

  if args[1] == "--force" then
    git_args[#git_args + 1] = args[1]
  elseif args[1] == "--force-with-lease" then
    -- force with lease
    git_args[#git_args + 1] = string.format("--force-with-lease=%s:%s", upstream_name, upstream.oid)
  end

  git_args[#git_args + 1] = upstream.remote

  git_args[#git_args + 1] = current.name .. ":" .. upstream_name

  self:run_command("git", git_args, true)
end

---GitStatus fetch menu
---@return Fugit2UITransientMenu
function GitStatus:_init_fetch_menu()
  local m = self:_init_menus(Menu.FETCH)
  m:on_submit(function(item_id, args)
    if item_id == "p" then
      self:fetch_from_pushremote(args["args"])
    elseif item_id == "u" then
      self:fetch_from_upstream(args["args"])
    end
  end)
  return m
end

---@param args string[]
function GitStatus:fetch_from_pushremote(args)
  ---@type string[]
  local git_args = { "fetch" }
  local remote = self._git.remote

  vim.list_extend(git_args, args)

  if remote then
    git_args[#git_args + 1] = remote.name
  end

  self:run_command("git", git_args, true)
end

---@param args string[]
function GitStatus:fetch_from_upstream(args)
  ---@type string[]
  local git_args = { "fetch" }
  local upstream = self._git.upstream

  vim.list_extend(git_args, args)

  if not upstream then
    error "[Fugit2] Upstream Not Found"
    return
  end

  git_args[#git_args + 1] = upstream.remote

  self:run_command("git", git_args, true)
end

---GitStatus Pull menu
function GitStatus:_init_pull_menu()
  local m = self:_init_menus(Menu.PULL)
  m:on_submit(function(item_id, args)
    if item_id == "p" then
      self:pull_from_pushremote(args["args"])
    elseif item_id == "u" then
      self:pull_from_upstream(args["args"])
    end
  end)
  return m
end

---@param args string[] git pull arguments
function GitStatus:pull_from_pushremote(args)
  ---@type string[]
  local git_args = { "pull" }
  local remote = self._git.remote

  vim.list_extend(git_args, args)

  if remote then
    git_args[#git_args + 1] = remote.name
  end

  self:run_command("git", git_args, true)
end

---@param args string[] git pull arguments
function GitStatus:pull_from_upstream(args)
  ---@type string[]
  local git_args = { "pull" }
  local upstream = self._git.upstream

  vim.list_extend(git_args, args)

  if not upstream then
    error "[Fugit2] Upstream Not Found"
    return
  end

  git_args[#git_args + 1] = upstream.remote

  self:run_command("git", git_args, true)
end

---Runs command and update git status
---@param cmd string
---@param args string[]
---@param refresh boolean whether to refresh after command succes
function GitStatus:run_command(cmd, args, refresh)
  local queue = self._states.command_queue

  if #queue > COMMAND_QUEUE_MAX then
    notifier.error "Command queue is full!"
    return
  end

  local command_id = utils.new_pid()
  queue[#queue + 1] = command_id

  if queue[1] == command_id then
    return self:_run_single_command(cmd, args, refresh)
  end

  local timer = uv.new_timer()
  if not timer then
    error "[Fugit2] Can't create timer"
  end

  notifier.info(string.format("Enqueued command %s %s", cmd, args[1] or ""))

  local tick = 0
  timer:start(0, 250, function()
    if tick > COMMAND_QUEUE_WAIT_TIME then
      timer:stop()
      timer:close()
      for i, id in ipairs(queue) do
        if id == command_id then
          table.remove(queue, i)
          break
        end
      end
      return
    elseif queue[1] == command_id then
      timer:stop()
      timer:close()
      vim.schedule(function()
        self:_run_single_command(cmd, args, refresh)
      end)
    end

    tick = tick + 250
  end)
end

---Runs single command and update git status
---@param cmd string
---@param args string[]
---@param refresh boolean whether to refresh after command succes
function GitStatus:_run_single_command(cmd, args, refresh)
  local bufnr = self.command_popup.bufnr
  local queue = self._states.command_queue

  self:focus_command()

  local cmd_line = "❯ " .. cmd .. " " .. table.concat(args, " ")
  local winid = self.command_popup.winid

  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(bufnr, "readonly", false)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local linenr = #lines
  if lines[1] and lines[1] ~= "" then
    vim.api.nvim_buf_set_lines(bufnr, #lines, -1, true, { cmd_line })
    vim.api.nvim_win_set_cursor(winid, { #lines, 0 })
    linenr = linenr + 1
  else
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, true, { cmd_line })
  end

  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_set_cursor(winid, { linenr, 0 })
    vim.api.nvim_feedkeys("zt", "n", true)
  end

  local timer, tick = uv.new_timer(), 0
  if not timer then
    error "[Fugit2] Can't create timer"
    return
  end

  local job = PlenaryJob:new {
    command = cmd,
    args = args,
    cwd = self._git.path,
    on_exit = vim.schedule_wrap(function(_, ret)
      table.remove(queue, 1)
      self._states.job = nil -- TODO: change this line
      if timer and timer:is_active() then
        timer:close()
      end

      if ret == 0 then
        notifier.info(string.format("Command %s %s SUCCESS", cmd, args[1] or ""))
        self:quit_command()
        if refresh then
          self:update_then_render()
        end
      elseif ret == -3 then
        vim.api.nvim_buf_set_lines(bufnr, linenr, -1, true, { "CANCELLED" })
        notifier.error(string.format("Command %s %s CANCELLED!", cmd, args[1] or ""))
      elseif ret == -5 then
        vim.api.nvim_buf_set_lines(bufnr, linenr, -1, true, { "TIMEOUT" })
        notifier.error(string.format("Command %s %s TIMEOUT!", cmd, args[1] or ""))
      else
        vim.api.nvim_buf_set_lines(bufnr, linenr, -1, true, { "FAILED " .. ret })
        notifier.error(string.format("Command %s %s FAILED!", cmd, args[1] or ""))
      end
    end),
    on_stdout = function(_, data)
      if data then
        local i = linenr
        vim.schedule(function()
          -- vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
          vim.api.nvim_buf_set_lines(bufnr, i, -1, true, { data })
          if vim.api.nvim_win_is_valid(winid) then
            vim.api.nvim_win_set_cursor(winid, { i + 1, 0 })
          end
        end)
        linenr = linenr + 1
      end
    end,
    on_stderr = function(_, data)
      if data then
        local i = linenr
        vim.schedule(function()
          -- vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
          vim.api.nvim_buf_set_lines(bufnr, i, -1, true, { data })
          if vim.api.nvim_win_is_valid(winid) then
            vim.api.nvim_win_set_cursor(winid, { i + 1, 0 })
          end
        end)
        linenr = linenr + 1
      end
    end,
  }
  self._states.job = job
  job:start()

  local wait_time = SERVER_TIMEOUT -- 12 seconds
  local tick_rate = 100

  timer:start(0, tick_rate, function()
    if tick * tick_rate > wait_time then
      timer:stop()
      timer:close()

      vim.schedule(function()
        if not pcall(function()
          job:co_wait(200)
        end) then
          job:shutdown(-5, utils.LINUX_SIGNALS.SIGTERM)
        end
      end)

      return
    end

    local idx = 1 + (tick % #utils.LOADING_CHARS)
    local char = utils.LOADING_CHARS[idx]

    vim.schedule(function()
      vim.api.nvim_buf_set_lines(bufnr, linenr, -1, true, { char })
    end)

    tick = tick + 1
  end)
end

---Quit/cancel current running command
function GitStatus:quit_command()
  if self._states.job then
    self._states.job:shutdown(-3, utils.LINUX_SIGNALS.SIGTERM)
  end

  self._layout:update(self._boxes.main)
  self:focus_file()
end

local MENU_INITS = {
  [Menu.BRANCH] = GitStatus._init_branch_menu,
  [Menu.COMMIT] = GitStatus._init_commit_menu,
  [Menu.DIFF] = GitStatus._init_diff_menu,
  [Menu.FETCH] = GitStatus._init_fetch_menu,
  [Menu.PULL] = GitStatus._init_pull_menu,
  [Menu.PUSH] = GitStatus._init_push_menu,
  [Menu.FORGE] = GitStatus._init_forge_menu,
}

---Menu handlers factory
---@param menu_type Fugit2GitStatusMenu menu to init
---@return fun() closure handler
function GitStatus:_menu_handlers(menu_type)
  local menus = self._menus

  return function()
    local menu_constructor = MENU_INITS[menu_type]

    local menu = menus[menu_type]
    if not menu and menu_constructor then
      menu = menu_constructor(self)
      menus[menu_type] = menu
    end
    menu:mount()
  end
end

-- Setup keymap and event handlers
function GitStatus:setup_handlers()
  local map_options = { noremap = true, nowait = true }
  local file_tree = self._views.files
  local commit_log = self._views.commits
  local states = self._states
  -- local popups = self._popups

  local exit_fn = function()
    self:unmount()
  end

  -- exit
  file_tree:map("n", { "q", "<esc>" }, exit_fn, map_options)
  file_tree:map("i", "<c-c>", exit_fn, map_options)
  commit_log:map("n", { "q", "<esc>" }, exit_fn, map_options)
  file_tree:on(event.BufUnload, function()
    self.closed = true
  end)
  -- popup:on(event.BufLeave, exit_fn)

  -- refresh
  file_tree:map("n", "r", function()
    self:update_then_render()
  end, map_options)

  -- collapse
  file_tree:map("n", "h", function()
    local node = file_tree.tree:get_node()

    if node and node:collapse() then
      file_tree:render()
    end
  end, map_options)

  -- collapse all
  file_tree:map("n", "H", function()
    local updated = false

    for _, node in pairs(file_tree.tree.nodes.by_id) do
      updated = node:collapse() or updated
    end

    if updated then
      file_tree:render()
    end
  end, map_options)

  -- Expand and move right
  file_tree:map("n", "l", function()
    local node = file_tree.tree:get_node()
    if node then
      if node:expand() then
        file_tree:render()
      end
      if not node:has_children() and states.side_panel == SidePanel.PATCH_VIEW then
        if states.patch_unstaged_shown then
          self._views.patch_unstaged:focus()
        elseif states.patch_staged_shown then
          self._views.patch_staged:focus()
        end
      end
    end
  end, map_options)

  -- Move to commit view
  file_tree:map("n", { "J", "<tab>" }, function()
    if states.side_panel == SidePanel.NONE then
      commit_log:focus()
    end
  end, map_options)
  file_tree:map("n", "K", "", map_options)

  -- Move back to file popup
  commit_log:map("n", { "K", "<tab>" }, function()
    if states.side_panel == SidePanel.NONE then
      file_tree:focus()
    end
  end, map_options)
  commit_log:map("n", "J", "", map_options)

  -- Quick jump commit
  commit_log:map("n", "j", "2j", map_options)
  commit_log:map("n", "k", "2k", map_options)

  -- copy commit id
  commit_log:map("n", "yy", function()
    local commit, _ = commit_log:get_commit()
    if commit then
      vim.api.nvim_call_function("setreg", { '"', commit.oid })
    end
  end, map_options)

  commit_log:map("n", "yc", function()
    local commit, _ = commit_log:get_commit()
    if commit then
      vim.api.nvim_call_function("setreg", { "+", commit.oid })
    end
  end, map_options)

  -- expand all
  file_tree:map("n", "L", function()
    local updated = false

    for _, node in pairs(file_tree.tree.nodes.by_id) do
      updated = node:expand() or updated
    end

    if updated then
      file_tree:render()
    end
  end, map_options)

  -- Patch view & move cursor
  states.last_patch_line = -1
  states.patch_staged_shown = false
  states.patch_unstaged_shown = false

  file_tree:on(event.CursorMoved, function()
    if states.side_panel == SidePanel.PATCH_VIEW then
      local node, linenr = file_tree:get_child_node_linenr()
      if node and linenr and linenr ~= states.last_patch_line then
        states.patch_unstaged_shown, states.patch_staged_shown = self:update_patch(node)
        if states.patch_unstaged_shown or states.patch_staged_shown then
          self:show_patch_view(states.patch_unstaged_shown, states.patch_staged_shown)
          states.last_patch_line = linenr
        end
      end
    end
  end)

  ---- Toggle patch views
  file_tree:map("n", "=", function()
    if states.side_panel == SidePanel.PATCH_VIEW then
      self:hide_patch_view()
    elseif states.side_panel == SidePanel.NONE then
      self:show_patch_for_current_file()
    end
  end, map_options)

  ---- Enter: collapse expand toggle, move to file buffer and diff
  file_tree:map("n", "<cr>", function()
    local node = file_tree.tree:get_node()
    if node and node:has_children() then
      if node:is_expanded() then
        node:collapse()
      else
        node:expand()
      end
      file_tree:render()
    -- elseif states.patch_shown then
    --   if states.patch_unstaged_shown then
    --     self._patch_unstaged:focus()
    --   elseif states.patch_staged_shown then
    --     self._patch_staged:focus()
    --   end
    elseif node then
      exit_fn()
      open_file(self._git.path, node.id)
    end
  end, map_options)

  --- Space/[-]: Add or remove index
  file_tree:map(
    "n",
    { "-", "<space>" },
    self:_index_add_reset_handler(false, TreeBase.IndexAction.ADD_RESET),
    map_options
  )

  --- [s]: stage file
  file_tree:map("n", "s", self:_index_add_reset_handler(false, TreeBase.IndexAction.ADD), map_options)

  --- [u]: unstage file
  file_tree:map("n", "u", self:_index_add_reset_handler(false, TreeBase.IndexAction.RESET), map_options)

  --- [D]/[x]: discard file changes
  -- file_tree:map("n", {"D", "x"}, self:index_add_reset_handler(false, false, false, true), map_options)
  self._prompts.discard_confirm:on_yes(self:_index_add_reset_handler(false, TreeBase.IndexAction.DISCARD))
  file_tree:map("n", { "D", "x" }, function()
    local node = file_tree.tree:get_node()
    if node then
      self._prompts.discard_confirm:set_text(NuiLine {
        NuiText("󰮈 Discard ", "Fugit2Unstaged"),
        NuiText(node.id, "Fugit2MenuHead"),
        NuiText "?",
      })
    end
    self._prompts.discard_confirm:show()
  end, map_options)

  --- Visual Space/[-]: Add remove for range
  file_tree:map(
    "v",
    { "-", "<space>" },
    self:_index_add_reset_handler(true, TreeBase.IndexAction.ADD_RESET),
    map_options
  )

  --- Visual [s]: stage files in range
  file_tree:map("v", "s", self:_index_add_reset_handler(true, TreeBase.IndexAction.ADD), map_options)

  --- Visual [u]: unstage files in range
  file_tree:map("v", "u", self:_index_add_reset_handler(true, TreeBase.IndexAction.RESET), map_options)

  --- Visual [x][d]: discard files in range
  file_tree:map("v", { "x", "d" }, function()
    self._prompts.discard_confirm:set_text(NuiLine {
      NuiText("󰮈 Discard selected changes?", "Fugit2Unstaged"),
    })
    self._prompts.discard_confirm:show()
  end, map_options)

  ---- Write index
  file_tree:map("n", "w", function()
    if self.index:write() == 0 then
      notifier.info "Index saved"
    end
  end, map_options)

  -- Commit Menu
  file_tree:map("n", "c", self:_menu_handlers(Menu.COMMIT), map_options)

  -- Amend confirm
  self._prompts.amend_confirm:on_yes(self:amend_confirm_yes_handler())

  -- Command popup
  self.command_popup:map("n", { "q", "<esc>" }, function()
    self:quit_command()
  end, map_options)

  -- Diff Menu
  file_tree:map("n", "d", self:_menu_handlers(Menu.DIFF), map_options)

  -- Branch Menu
  file_tree:map("n", "b", self:_menu_handlers(Menu.BRANCH), map_options)

  -- Push menu
  file_tree:map("n", "P", self:_menu_handlers(Menu.PUSH), map_options)

  -- Fetch menu
  file_tree:map("n", "f", self:_menu_handlers(Menu.FETCH), map_options)

  -- Pull menu
  file_tree:map("n", "p", self:_menu_handlers(Menu.PULL), map_options)

  -- Forge menu
  file_tree:map("n", "N", self:_menu_handlers(Menu.FORGE), map_options)
end

return GitStatus
