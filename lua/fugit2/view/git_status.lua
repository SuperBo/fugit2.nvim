-- Fugit2 Git Status module

local uv = vim.loop

local NuiLayout = require "nui.layout"
local NuiLine = require "nui.line"
local NuiText = require "nui.text"
local NuiPopup = require "nui.popup"
local Object = require "nui.object"
local event = require "nui.utils.autocmd".event
local async = require "plenary.async"
local async_utils = require "plenary.async.util"
local PlenaryJob = require "plenary.job"
local iterators = require "plenary.iterators"

local UI = require "fugit2.view.components.menus"
local GitStatusTree = require "fugit2.view.components.file_tree_view"
-- local GitBranchTree = require "fugit2.view.components.branch_tree_view"
local PatchView = require "fugit2.view.components.patch_view"
local LogView = require "fugit2.view.components.commit_log_view"
local git2 = require "fugit2.git2"
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


local FILE_WINDOW_WIDTH = 58
local GIT_LOG_MAX_COMMITS = 8

-- ======================
-- | Helper enum buffer |
-- ======================

---@enum Fugit2GitStatusCommitMode
local CommitMode = {
  CREATE = 1,
  REWORD = 2,
  EXTEND = 3,
  AMEND  = 4,
}


---@enum Fugit2GitStatusMenu
local Menu = {
  BRANCH = 1,
  COMMIT = 2,
  DIFF   = 3,
  FETCH  = 4,
  PULL   = 5,
  PUSH   = 6,
  REBASE = 7,
}

-- ===================
-- | Main git status |
-- ===================

local LOADING_CHARS = {
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
}


---@enum Fugit2GitStatusSidePanel
local SidePanel = {
  NONE       = 0,
  PATCH_VIEW = 1,
}


---@class Fugit2GitStatusView
---@field info_popup NuiPopup
---@field input_popup NuiPopup
---@field repo GitRepository
---@field closed boolean
local GitStatus = Object("Fugit2GitStatusView")


---Inits GitStatus.
---@param ns_id integer
---@param repo GitRepository
---@param last_window integer
---@param current_file string
function GitStatus:init(ns_id, repo, last_window, current_file)
  self.ns_id = -1
  if ns_id then
    self.ns_id = ns_id
  end

  self.closed = false
  ---@class Fugit2GitStatusGitStates
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
  self._git = {
    head = nil, ahead = 0, behind = 0,
    index_updated = false,
    unstaged_diff = {}, staged_diff = {},
  }

  if repo ~= nil then
    self.repo = repo
    local index, sig, walker, err

    index, err = repo:index()
    if index == nil then
      error("[Fugit2] libgit2 Error " .. err)
    end
    self.index = index

    sig, err = repo:signature_default()
    if sig then
      self._git.signature = sig
    end

    walker, err = repo:walker()
    if walker then
      self._git.walker = walker
    end
  else
    error("[Fugit2] Null repo")
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
      buftype  = "nofile",
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
    },
    buf_options = buf_readonly_opts,
  }

  self.input_popup = NuiPopup {
    ns_id = ns_id,
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
      }
    },
    win_options = {
      winhighlight = win_hl,
    },
    buf_options = {
      modifiable = true,
      filetype = "gitcommit",
    }
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
      }
    },
    win_options = {
      winhighlight = win_hl,
    },
    buf_options = buf_readonly_opts,
  }

  ---@type Fugit2CommitLogView
  self._views.commits = LogView(self.ns_id, "  Commits ", false)
  ---@type Fugit2GitStatusTree
  self._views.files = GitStatusTree(
    self.ns_id, " 󰙅 Files ", "[b]ranches [c]ommits [d]iff", "FloatFooter"
  )

  -- menus
  local amend_confirm = UI.Confirm(
    self.ns_id,
    NuiLine { NuiText("This commit has already been pushed to upstream, do you really want to modify it?") }
  )
  self._prompts = {
    amend_confirm = amend_confirm,
  }
  ---@type { [integer]: Fugit2UITransientMenu }
  self._menus = {}

  -- setup others

  vim.api.nvim_buf_set_extmark(self.input_popup.bufnr, self.ns_id, 0, 0, {
    id = 1,
    end_row = 0,
    virt_text = {
      {"commit message", "Comment"}
    },
    virt_text_pos = "right_align",
    virt_text_hide = true,
  })

  ---@type NuiLine[]
  self._status_lines = {}

  -- setup layout
  ---@type { [string]: NuiLayout.Box }
  self._boxes = {
    main = NuiLayout.Box({
        NuiLayout.Box(self.info_popup, { size = 6 }),
        NuiLayout.Box(self._views.files.popup, { grow = 1 }),
        NuiLayout.Box(self._views.commits.popup, { size = 10 }),
      }, { dir = "col" }
    ),
    main_row = NuiLayout.Box(self._views.files.popup, { grow = 1 })
  }
  self._layout_opts = {
    main = {
      relative = "editor",
      position = "50%",
      size = { width = 100, height = "60%" }
    },
    diff = {
      position = "50%",
      size = { width = "80%", height = "60%" }
    }
  }
  self._layout = NuiLayout(
    self._layout_opts.main,
    self._boxes.main
  )


  -- state variables for UI
  ---@class Fugit2GitStatusInternal
  ---@field last_window integer
  ---@field commit_mode Fugit2GitStatusCommitMode
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
  self._states = {
    last_window = last_window,
    current_file = current_file,
    commit_mode = CommitMode.CREATE,
    side_panel  = SidePanel.NONE,
    command_queue = {},
  }

  -- keymaps
  self:setup_handlers()

  async.run(
    function() self:update() end, -- get git content
    async_utils.scheduler(function()
      self:render()
      self:scroll_to_active_file()
    end)
  )
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
        NuiText(" "),
        NuiText(utils.get_ahead_behind_text(git.push_target.ahead, git.push_target.behind), "Fugit2Count")
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
        NuiText(" "),
        NuiText(utils.get_ahead_behind_text(git.upstream.ahead, git.upstream.behind), "Fugit2Count")
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
  local menu_items, menu_title, arg_items
  local title_hl = "Fugit2FloatTitle"
  local head_hl = "Fugit2MenuHead"
  local states = self._states
  local git = self._git

  if menu_type == Menu.COMMIT then
    menu_title = NuiText(" Committing ", title_hl)
    menu_items = {
      { texts = { NuiText("  Create ", head_hl) } },
      { texts = { NuiText(" Commit ") }, key = "c" },
      { texts = { NuiText("  Edit ", head_hl), NuiText("HEAD ", "Fugit2Header") } },
      { texts = { NuiText("󰦒 Extend") }, key = "e" },
      { texts = { NuiText("󰧭 Reword") }, key = "r" },
      { texts = { NuiText("󰣪 Amend") },  key = "a" },
      { texts = { NuiText(" 󰽜 Edit ", head_hl) } },
      { texts = { NuiText("󰇾 Fixup") },  key = "f" },
      { texts = { NuiText("󰶯 Squash") },  key = "s" },
      { texts = { NuiText(" Absorb") },  key = "b" },
      { texts = { NuiText("  Log ", head_hl) } },
      { texts = { NuiText("󱁉 Graph") },  key = "g" },
    }
  elseif menu_type == Menu.DIFF then
    menu_title = NuiText(" Diffing ", title_hl)
    menu_items = {
      { texts = { NuiText("Diffview") }, key = "d" }
    }
  elseif menu_type == Menu.BRANCH then
    menu_title = NuiText(" Branching ", title_hl)
    menu_items = {
      { texts = { NuiText("Checkout", head_hl) } },
      { texts = { NuiText("Branch/revision") }, key = "b" }
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
        text = NuiText("Force with lease"),
        key = "-f", arg = "--force-with-lease",
        type = UI.INPUT_TYPE.RADIO, model = "force"
      },
      {
        text = NuiText("Force"),
        key = "-F", arg = "--force",
        type = UI.INPUT_TYPE.RADIO, model = "force"
      },
    }
    menu_items = {
      { texts = { NuiText("  Push ", head_hl), states.current_text, NuiText(" to ", head_hl) } },
      { texts = { NuiText("@pushRemote") }, key = "p" }
    }
    menu_items = prepare_pull_push_items(git, menu_items)
  elseif menu_type == Menu.FETCH then
    menu_title = NuiText("  Fetching ", title_hl)
    arg_items = {
      {
        text = NuiText("Prune deleted branches"),
        key = "-p", arg = "--prune",
        type = UI.INPUT_TYPE.CHECKBOX, model = "args"
      },
      {
        text = NuiText("Fetch all tags"),
        key = "-t", arg = "--tags",
        type = UI.INPUT_TYPE.CHECKBOX, model = "args"
      },
    }
    menu_items = {
      { texts = { NuiText("  Fetch from ", head_hl) } },
      { texts = { NuiText("@pushRemote") }, key = "p" },
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
        text = NuiText("Fast-forward only"),
        key = "-f", arg = "--ff-only",
        type = UI.INPUT_TYPE.CHECKBOX, model = "args"
      },
      {
        text = NuiText("Rebase local commits"),
        key = "-r", arg = "--rebase",
        type = UI.INPUT_TYPE.CHECKBOX, model = "args"
      },
      {
        text = NuiText("Autostash"),
        key = "-a", arg = "autostash",
        type = UI.INPUT_TYPE.CHECKBOX, model = "args"
      },
      {
        text = NuiText("Fetch all tags"),
        key = "-t", arg = "--tags",
        type = UI.INPUT_TYPE.CHECKBOX, model = "args"
      }
    }
    menu_items = {
      { texts = { NuiText("  Pull into ", head_hl), states.current_text, NuiText(" from ", head_hl) } },
      { texts = { NuiText("@pushRemote") }, key = "p" },
    }
    menu_items = prepare_pull_push_items(git, menu_items)
  end

  return UI.Menu(self.ns_id, menu_title, menu_items, arg_items)
end


---Inits Patch View popup
function GitStatus:_init_patch_views()
  local patch_unstaged = PatchView(self.ns_id, "Unstaged", "Fugit2Unstaged")
  local patch_staged = PatchView(self.ns_id, "Staged", "Fugit2Staged")
  local opts = { noremap = true, nowait= true }
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

  -- Commit menu
  local commit_menu_handler = self:_menu_handlers(Menu.COMMIT)
  patch_unstaged:map("n", "c", commit_menu_handler, opts)
  patch_staged:map("n", "c", commit_menu_handler, opts)

  -- Diff menu
  local diff_menu_handler = self:_menu_handlers(Menu.DIFF)
  patch_unstaged:map("n", "d", diff_menu_handler, opts)
  patch_staged:map("n", "d", diff_menu_handler, opts)

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
      vim.cmd("normal! l")
    end
  end, opts)

  -- [=]: turn off
  local turn_off_patch_fn = function()
    self:focus_file()
    vim.api.nvim_feedkeys("=", "m", true)
  end
  patch_unstaged:map("n", "=", turn_off_patch_fn, opts)
  patch_staged:map("n", "=", turn_off_patch_fn, opts)

  local diff_apply_fn = function(diff_str)
    local diff, err = git2.Diff.from_buffer(diff_str)
    if not diff then
      vim.notify("[Fugit2] Failed to construct git2 diff, code " .. err, vim.log.levels.ERROR)
      return -1
    end

    err = self.repo:apply_index(diff)
    if err ~= 0 then
      vim.notify("[Fugit2] Failed to apply partial diff, code " .. err, vim.log.levels.ERROR)
      return err
    end
    return 0
  end

  local diff_update_fn = function(node)
    -- update node status in file tree
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
      vim.notify("[Fugit2] Failed to get hunk", vim.log.levels.ERROR)
      return
    end

    if diff_apply_fn(diff_str) == 0 then
      local node, _ = tree:get_child_node_linenr()
      if node then
        diff_update_fn(node)
      end
    end
  end, opts)

  -- [-]/[u]: Unstage handling
  patch_staged:map("n", { "-", "u" }, function()
    local node, _ = tree:get_child_node_linenr()
    if not node then
      return
    end

    local err = 0
    if node.istatus == "A" then
      err = self.repo:reset_default({ node.id })
    else
      local diff_str = patch_staged:get_diff_hunk_reversed()
      if not diff_str then
        vim.notify("[Fugit2] Failed to get revere hunk", vim.log.levels.ERROR)
        return
      end
      err = diff_apply_fn(diff_str)
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

    if diff_apply_fn(diff_str) == 0 then
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

    if diff_apply_fn(diff_str) == 0 then
      local node, _ = tree:get_child_node_linenr()
      if node then
        diff_update_fn(node)
      end
    end
  end, opts)
end


---Updates git status.
function GitStatus:update()
  utils.list_clear(self._status_lines)
  -- clean cached menus
  self._menus[Menu.PUSH] = nil
  self._menus[Menu.PULL] = nil
  -- clean cached diffs
  if self._git.unstaged_diff then
    for k, _ in pairs(self._git.unstaged_diff) do
      self._git.unstaged_diff[k] = nil
    end
  end
  if self._git.staged_diff then
    for k, _ in pairs(self._git.staged_diff) do
      self._git.staged_diff[k] = nil
    end
  end

  local status_files, status_head, status_upstream, err
  ---@type NuiLine[]
  local lines = self._status_lines

  status_head, status_upstream, err = self.repo:status_head_upstream()
  if not status_head then
    local line = NuiLine { NuiText("HEAD  ", "Fugit2Header") }

    -- Get status head only
    local head, _ = self.repo:reference_lookup("HEAD")
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
  else
    -- update status panel
    self._git.head = status_head

    local remote, _ = self.repo:remote_default()
    if remote then
      self._git.remote = {
        name = remote.name,
        url = remote.url,
        push_url = remote.push_url
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
      head_line:append("     ")
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

    local author_width = math.max(
      status_head.author:len(),
      status_upstream and status_upstream.author:len() or 0
    )
    local author_format = " %-" .. author_width .. "s"

    local head_icon = utils.get_git_namespace_icon(status_head.namespace)

    self._states.current_text = NuiText( head_icon .. status_head.name, "Fugit2BranchHead")

    if ahead_behind == 0 then
      head_line:append(
        string.format(branch_format, head_icon, status_head.name),
        "Fugit2BranchHead"
      )
    else
      head_line:append(head_icon .. status_head.name, "Fugit2BranchHead")
      local padding = (
        branch_width
        - status_head.name:len()
        - (ahead > 0 and 2 or 0)
        - (behind > 0 and 2 or 0)
      )
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
        NuiText("This commit has already been pushed to "),
        NuiText(status_upstream.name, "Fugit2SymbolicRef"),
        NuiText(", do you really want to modify it?")
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
            behind = status_upstream.behind
          }
        else
          local push_target_id, _ = self.repo:reference_name_to_id(push_ref)
          if push_target_id and status_head.oid then
            local ahead1, behind1 = self.repo:ahead_behind(status_head.oid, push_target_id)
            self._git.push_target = {
              name   = push_name,
              oid    = tostring(push_target_id),
              ahead  = ahead1 or 0,
              behind = behind1 or 0
            }
          end
        end
      end
    end

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
        local parents = vim.tbl_map(
          function(p) return p:tostring(id_len) end,
          commit:parent_oids()
        )

        local id_str = oid:tostring(id_len)
        local refs = {}
        if oid == status_head.oid then
          refs[1] = status_head.refname
        end
        if status_upstream and oid == status_upstream.oid then
          refs[#refs+1] = "refs/remotes/" .. status_upstream.name
        end

        commits[#commits+1] = LogView.CommitNode(
          id_str,
          commit:message(),
          commit:author(),
          parents,
          refs
        )

        if #commits > GIT_LOG_MAX_COMMITS then
          break
        end
      end

      self._views.commits:update(commits, self._git.remote_icons)
    end
  end

  status_files, err = self.repo:status()
  if status_files then
    -- update files tree
    self._views.files:update(status_files)
  end
end


-- Renders git status
function GitStatus:render()
  vim.api.nvim_buf_set_option(self.info_popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(self.info_popup.bufnr, "readonly", false)

  for i, line in ipairs(self._status_lines) do
    line:render(self.info_popup.bufnr, self.ns_id, i)
  end

  self._views.files:render()
  self._views.commits:render()
  -- self._branches_view:render()

  vim.api.nvim_buf_set_option(self.info_popup.bufnr, "readonly", true)
  vim.api.nvim_buf_set_option(self.info_popup.bufnr, "modifiable", false)
end


---Scrolls to active file
function GitStatus:scroll_to_active_file()
  local current_file = self._states.current_file
  local _, linenr = self._views.files.tree:get_node("-" .. current_file)
  if linenr then
    vim.api.nvim_win_set_cursor(0, { linenr, 1 })
  end
end


function GitStatus:mount()
  self._layout:mount()
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

  self._prompts.amend_confirm:unmount()
  self._menus = {}
  self.command_popup:unmount()
  self.input_popup:unmount()
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


---Add/reset file entries handler.
---@param is_visual_mode boolean whether this handler is called in visual mode.
---@param add boolean add to index enable
---@param reset boolean reset from enable
---@return fun()
function GitStatus:index_add_reset_handler(is_visual_mode, add, reset)
  local tree = self._views.files
  local git = self._git
  local states = self._states

  return function()
    local nodes

    if not is_visual_mode then
      local node, _ = tree.tree:get_node()
      nodes = iterators.iter({node})
    else
      local cursor_start = vim.fn.getpos("v")[2]
      local cursor_end = vim.fn.getpos(".")[2]
      if cursor_end < cursor_start then
        cursor_start, cursor_end = cursor_end, cursor_start
      end

      nodes = iterators.range(
        cursor_start, cursor_end, 1
      ):map(function(linenr)
        local node = tree.tree:get_node(linenr)
        return node
      end)

      vim.api.nvim_feedkeys(utils.KEY_ESC, "n", false)
    end

    nodes = nodes:filter(function(node) return not node:has_children() end)

    local results = nodes:map(function(node)
      local is_updated, is_refresh = tree:index_add_reset(self.repo, self.index, add, reset, node)

      if is_updated then
        -- remove cached diff
        git.staged_diff[node.id] = nil
        git.unstaged_diff[node.id] = nil
      end

      return { is_updated, is_refresh }
    end):tolist()

    local updated = utils.list_any(function(r) return r[1] end, results)
    local refresh = utils.list_any(function(r) return r[2] end, results)

    if not updated then
      return
    end

    if refresh then
      self:update()
      self:render()
    else
      tree:render()
    end

    git.index_updated = true

    -- old node at current cursor maybe deleted
    local node, linenr = tree.tree:get_node()
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
end

function GitStatus:focus_input()
  self._layout:update(NuiLayout.Box(
    {
      NuiLayout.Box(self.info_popup, { size = 6 }),
      NuiLayout.Box(self.input_popup, { size = 6 }),
      NuiLayout.Box(self._boxes.main_row, { dir = "row", grow = 1 }),
    },
    { dir = "col" }
  ))
  vim.api.nvim_set_current_win(self.input_popup.winid)
end

function GitStatus:focus_file()
  self._views.files:focus()
end


---Hides input popup
---@param back_to_main boolean Reset back to main layout
function GitStatus:hide_input(back_to_main)
  vim.api.nvim_buf_set_lines(
    self.input_popup.bufnr,
    0, -1, true, {}
  )

  local layout = self._layout

  if back_to_main or self._states.side_panel == SidePanel.NONE then
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
    self.input_popup.bufnr, 0, -1, true,
    vim.split(self._git.head.message, "\n", { plain = true, trimempty = true })
  )
end


---@param signature GitSignature
---@param message string
---@return string? prettified
local function check_signature_message(signature, message)
  if not signature then
    vim.notify("No default author", vim.log.levels.ERROR)
    return nil
  end

  if message == "" then
    vim.notify("Empty commit message", vim.log.levels.ERROR)
    return nil
  end

  local prettified, err = git2.message_prettify(message)
  if err ~= 0 then
    vim.notify("Failed to clean message", vim.log.levels.ERROR)
    return nil
  end

  return prettified
end


---Creates a commit
---@param message string
function GitStatus:_git_create_commit(message)
  local prettified = check_signature_message(self._git.signature, message)

  if self._git.signature and prettified then
    self:write_index()
    local commit_id, err = self.repo:commit(self.index, self._git.signature, prettified)
    if commit_id then
      vim.notify("[Fugit2] New commit " .. commit_id:tostring(8), vim.log.levels.INFO)
      self:hide_input(true)
      self:update()
      self:render()
    else
      vim.notify("Failed to create commit, code: " .. err, vim.log.levels.ERROR)
    end
  end
end


---Extends HEAD commit
---add files in index to HEAD commit
function GitStatus:_git_extend_commit()
  self:write_index()
  local commit_id, err = self.repo:amend_extend(self.index)
  if commit_id then
    vim.notify("[Fugit2] Extend HEAD " .. commit_id:tostring(8), vim.log.levels.INFO)
    self:update()
    self:render()
  else
    vim.notify("Failed to extend HEAD, code: " .. err, vim.log.levels.ERROR)
  end
end


---Reword HEAD commit
---change commit message of HEAD commit
---@param message string commit message
function GitStatus:_git_reword_commit(message)
  local prettified = check_signature_message(self._git.signature, message)

  if self._git.signature and prettified then
    local commit_id, err = self.repo:amend_reword(self._git.signature, prettified)
    if commit_id then
      vim.notify("Reword HEAD " .. commit_id:tostring(8), vim.log.levels.INFO)
      self:hide_input(false)
      self:update()
      self:render()
    else
      vim.notify("Failed to reword HEAD, code: " .. err, vim.log.levels.ERROR)
    end
  end
end

---Amend HEAD commit
---add files from index and also change message or HEAD commit
---@param message string
function GitStatus:_git_amend_commit(message)
  local prettified = check_signature_message(self._git.signature, message)
  if self._git.signature and prettified then
    self:write_index()
    local commit_id, err = self.repo:amend(self.index, self._git.signature, prettified)
    if commit_id then
      vim.notify("Amend HEAD " .. commit_id:tostring(8), vim.log.levels.INFO)
      self:hide_input(true)
      self:update()
      self:render()
    else
      vim.notify("Failed to amend commit, code: " .. err, vim.log.levels.ERROR)
    end
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
      vim.notify("[Fugit2] Empty commit!", vim.log.levels.WARN)
    end
  end

  local title = string.format(
    " %s -  %s %s%s%s",
    init_str, tostring(self._git.signature),
    file_changed > 0 and string.format("%d 󰈙", file_changed) or "",
    insertions > 0 and string.format(" +%d", insertions) or "",
    deletions > 0 and string.format(" -%d", deletions) or ""
  )
  self.input_popup.border:set_text(
    "top",
    NuiText(title, "Fugit2MessageHeading"),
    "left"
  )
end


function GitStatus:commit_create()
  self._states.commit_mode = CommitMode.CREATE

  self:_set_input_popup_commit_title("Create commit", true, true)

  self:focus_input()
  vim.cmd.startinsert()
end


function GitStatus:commit_extend()
  self._states.commit_mode = CommitMode.EXTEND

  if self._git.ahead == 0 then
    self._prompts.amend_confirm:show()
    return
  end

  self:_git_extend_commit()
end


---@param is_reword boolean reword only mode
function GitStatus:commit_amend(is_reword)
  self._states.commit_mode = is_reword and CommitMode.REWORD or CommitMode.AMEND

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
      self:_git_extend_commit()
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
  m:on_submit(function(item_id, _)
    if item_id == "c" then
      self:commit_create()
    elseif item_id == "e" then
      self:commit_extend()
    elseif item_id == "r" then
      self:commit_amend(true)
    elseif item_id == "a" then
      self:commit_amend(false)
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
        vim.notify("Failed to get unstaged diff " .. err, vim.log.levels.ERROR)
        goto git_status_update_patch_index
      end
      patches, err = diff:patches(false)
      if #patches == 0 then
        vim.notify("Failed to get unstage patch " .. err, vim.log.levels.ERROR)
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
        vim.notify("Failed to get unstaged diff " .. err, vim.log.levels.ERROR)
        goto git_status_update_patch_end
      end
      patches, err = diff:patches(false)
      if #patches == 0 then
        vim.notify("Failed to get unstage patch " .. err, vim.log.levels.ERROR)
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
        NuiLayout.Box(self._views.files.popup, { size = FILE_WINDOW_WIDTH }),
        NuiLayout.Box(self._views.patch_unstaged.popup, { grow = 1 }),
        NuiLayout.Box(self._views.patch_staged.popup, { grow = 1 })
      })
    end
  elseif unstaged then
    row = self._boxes.patch_unstaged
    if not row then
      row = utils.update_table(self._boxes, "patch_unstaged", {
        NuiLayout.Box(self._views.files.popup, { size = FILE_WINDOW_WIDTH }),
        NuiLayout.Box(self._views.patch_unstaged.popup, { grow = 1 }),
      })
    end
  else
    row = self._boxes.patch_staged
    if not row then
      row = utils.update_table(self._boxes, "patch_staged", {
        NuiLayout.Box(self._views.files.popup, { size = FILE_WINDOW_WIDTH }),
        NuiLayout.Box(self._views.patch_staged.popup, { grow = 1 })
      })
    end
  end

  self._boxes.main_row = row
  self._layout:update(self._layout_opts.diff, NuiLayout.Box(
    {
      NuiLayout.Box(self.info_popup, { size = 6 }),
      NuiLayout.Box(row, { dir = "row", grow = 1 }),
    },
    { dir = "col" }
  ))
  self._states.side_panel = SidePanel.PATCH_VIEW
end

function GitStatus:hide_patch_view()
  self._layout:update(self._layout_opts.main, self._boxes.main)
  self._boxes.main_row = NuiLayout.Box(self._views.files.popup, { grow = 1 })
  self._states.side_panel = SidePanel.NONE
end

---GitStatus Diff Menu
---@return Fugit2UITransientMenu
function GitStatus:_init_diff_menu()
  local m = self:_init_menus(Menu.DIFF)
  m:on_submit(function(item_id, _)
    if item_id == "d" then
      local node, _ = self._views.files:get_child_node_linenr()
      if node and vim.fn.exists(":DiffviewOpen") > 0 then
        self:unmount()
        vim.cmd({ cmd = "DiffviewOpen", args = { "--selected-file=" .. vim.fn.fnameescape(node.id) } })
      end
    end
  end)
  return m
end

---GitStatus Branch Menu
---@return Fugit2UITransientMenu
function GitStatus:_init_branch_menu()
  local m = self:_init_menus(Menu.BRANCH)
  m:on_submit(function(item_id, _)
    if item_id == "b" then
      if vim.fn.exists(":Telescope") then
        self:unmount()
        vim.cmd({ cmd = "Telescope", args = { "git_branches"} })
      else
        vim.notify("[Fugit2] No telescope")
      end
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
    git_args[#git_args+1] = "-u"
  end

  if args[1] == "--force" then
    git_args[#git_args+1] = args[1]
  elseif args[1] == "--force-with-lease" then
    --force with lease
    local lease = args[1]
    if current then
      lease = lease .. "=" .. current.name

      if git.push_target then
        lease = lease .. ":" .. git.push_target.oid
      end
    end
    git_args[#git_args+1] = lease
  end

  if remote then
    git_args[#git_args+1] = remote.name
  end
  if current then
    git_args[#git_args+1] = current.name .. ":" .. current.name
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
    error("[Fugit2] Upstream Not Found")
    return
  end

  local upstream_names = vim.split(upstream.name, "/", { plain = true })
  if #upstream_names < 2 then
    error("[Fugit2] Invalid upstream name")
    return
  end

  if args[1] == "--force" then
    git_args[#git_args+1] = args[1]
  elseif args[1] == "--force-with-lease" then
    -- force with lease
    git_args[#git_args+1] = string.format("--force-with-lease=%s:%s", upstream_names[2], upstream.oid)
  end

  git_args[#git_args+1] = upstream.remote

  git_args[#git_args+1] = current.name .. ":" .. upstream_names[2]

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
    git_args[#git_args+1] = remote.name
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
    error("[Fugit2] Upstream Not Found")
    return
  end

  git_args[#git_args+1] = upstream.remote

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
    git_args[#git_args+1] = remote.name
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
    error("[Fugit2] Upstream Not Found")
    return
  end

  git_args[#git_args+1] = upstream.remote

  self:run_command("git", git_args, true)
end


---Runs command and update git status
---@param cmd string
---@param args string[]
---@param refresh boolean whether to refresh after command succes
function GitStatus:run_command(cmd, args, refresh)
  local queue = self._states.command_queue

  if #queue > COMMAND_QUEUE_MAX then
    vim.notify("[Fugit2] Command queue is full!", vim.log.levels.ERROR)
    return
  end

  local command_id = utils.new_pid()
  queue[#queue+1] = command_id

  if queue[1] == command_id then
    return self:_run_single_command(cmd, args, refresh)
  end

  local timer = uv.new_timer()
  if not timer then
    error("[Fugit2] Can't create timer")
  end

  vim.notify(string.format("[Fugit2] Enqueued command %s %s", cmd, args[1] or ""))

  local tick = 0
  timer:start(0, 250, function()
    if tick > COMMAND_QUEUE_WAIT_TIME then
      timer:stop()
      for i, id in ipairs(queue) do
        if id == command_id then
          table.remove(queue, i)
          break
        end
      end
      return
    elseif queue[1] == command_id then
      timer:stop()
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

  self._layout:update(NuiLayout.Box(
    {
      NuiLayout.Box(self.info_popup, { size = 6 }),
      NuiLayout.Box(self.command_popup, { size = 6 }),
      NuiLayout.Box(self._boxes.main_row, { dir = "row", grow = 1 })
    },
    { dir = "col" }
  ))

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
    error("[Fugit2] Can't create timer")
    return
  end

  local job = PlenaryJob:new({
    command = cmd,
    args = args,
    on_exit = vim.schedule_wrap(function(_, ret)
      table.remove(queue, 1)
      self._states.job = nil -- TODO: change this line
      if timer and timer:is_active() then
        timer:close()
      end

      if ret == 0 then
        vim.notify(
          string.format("[Fugit2] Command %s %s SUCCESS", cmd, args[1] or ""),
          vim.log.levels.INFO
        )
        self:quit_command()
        if refresh then
          self:update()
          self:render()
        end
      elseif ret == -3 then
        vim.api.nvim_buf_set_lines(bufnr, linenr, -1, true, { "CANCELLED" })
        vim.notify(
          string.format("[Fugit2] Command %s %s CANCELLED!", cmd, args[1] or ""),
          vim.log.levels.ERROR
        )
      elseif ret == -5 then
        vim.api.nvim_buf_set_lines(bufnr, linenr, -1, true, { "TIMEOUT" })
        vim.notify(
          string.format("[Fugit2] Command %s %s TIMEOUT!", cmd, args[1] or ""),
          vim.log.levels.ERROR
        )
      else
        vim.api.nvim_buf_set_lines(bufnr, linenr, -1, true, { "FAILED " .. ret })
        vim.notify(
          string.format("[Fugit2] Command %s %s FAILED!", cmd, args[1] or ""),
          vim.log.levels.ERROR
        )
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
    end
  })
  self._states.job = job
  job:start()

  local wait_time = SERVER_TIMEOUT -- 12 seconds
  local tick_rate = 100

  timer:start(0, tick_rate, function()
    if tick * tick_rate > wait_time then
      timer:close()

      vim.schedule(function()
        if not pcall(function() job:co_wait(200) end) then
          job:shutdown(-5, utils.LINUX_SIGNALS.SIGTERM)
        end
      end)

      return
    end

    local idx = 1 + (tick % #LOADING_CHARS)
    local char = LOADING_CHARS[idx]

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
  [Menu.DIFF]   = GitStatus._init_diff_menu,
  [Menu.FETCH]  = GitStatus._init_fetch_menu,
  [Menu.PULL]   = GitStatus._init_pull_menu,
  [Menu.PUSH]   = GitStatus._init_push_menu,
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
  file_tree:map("n", {"q", "<esc>"}, exit_fn, map_options)
  file_tree:map("i", "<c-c>", exit_fn, map_options)
  commit_log:map("n", {"q", "<esc>"}, exit_fn, map_options)
  file_tree:on(event.BufUnload, function()
    self.closed = true
  end)
  -- popup:on(event.BufLeave, exit_fn)

  -- refresh
  file_tree:map("n", "r", function ()
    self:update()
    self:render()
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
  end, map_options)

  ---- Enter: collapse expand toggle, move to file buffer and diff
  file_tree:map("n", "<cr>", function ()
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
      vim.cmd.edit(vim.fn.fnameescape(node.id))
    end
  end, map_options)

  ---- Space/[-]: Add or remove index
  file_tree:map("n", { "-", "<space>" }, self:index_add_reset_handler(false, true, true), map_options)

  ---- [s]: stage file
  file_tree:map("n", "s", self:index_add_reset_handler(false, true, false), map_options)

  ---- [u]: unstage file
  file_tree:map("n", "u", self:index_add_reset_handler(false, false, true), map_options)

  ---- Visual Space/[-]: Add remove for range
  file_tree:map("v", { "-", "<space>" }, self:index_add_reset_handler(true, true, true), map_options)

  --- Visual [s]: stage files in range
  file_tree:map("v", "s", self:index_add_reset_handler(true, true, false), map_options)

  --- Visual [u]: unstage files in range
  file_tree:map("v", "u", self:index_add_reset_handler(true, false, true), map_options)

  ---- Write index
  file_tree:map("n", "w",
    function ()
      if self.index:write() == 0 then
        vim.notify("[Fugit2] Index saved", vim.log.levels.INFO)
      end
    end,
    map_options
  )

  -- Commit Menu
  file_tree:map("n", "c", self:_menu_handlers(Menu.COMMIT), map_options)

  -- Amend confirm
  self._prompts.amend_confirm:on_yes(self:amend_confirm_yes_handler())

  -- Message input
  self.input_popup:map("n", { "q", "<esc>" }, function()
    self:hide_input(false)
  end, map_options)

  self.input_popup:map("i", "<c-c>", "<esc>q", { nowait = true })

  local input_enter_fn = function()
    local message = vim.trim(table.concat(
      vim.api.nvim_buf_get_lines(self.input_popup.bufnr, 0, -1, true),
      "\n"
    ))
    if states.commit_mode == CommitMode.CREATE then
      self:_git_create_commit(message)
    elseif states.commit_mode == CommitMode.REWORD then
      self:_git_reword_commit(message)
    elseif states.commit_mode == CommitMode.AMEND then
      self:_git_amend_commit(message)
    end
  end
  self.input_popup:map("n", "<cr>", input_enter_fn, map_options)
  self.input_popup:map("i", "<c-cr>", "<esc><cr>", { nowait = true })

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
end


return GitStatus
