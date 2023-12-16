-- NUI Git helper module

local NuiLayout = require "nui.layout"
local NuiLine = require "nui.line"
local NuiText = require "nui.text"
local NuiTree = require "nui.tree"
local NuiPopup = require "nui.popup"
local NuiMenu = require "nui.menu"
local Object = require "nui.object"
local event = require "nui.utils.autocmd".event
local WebDevIcons = require "nvim-web-devicons"

local UI = require "fugit2.view.components.menus"
local PatchView = require "fugit2.view.components.patch_view"
local DiffView = require "fugit2.view.components.diff_view"
local git2 = require "fugit2.git2"
local utils = require "fugit2.utils"


-- =================
-- |  Status tree  |
-- =================


---@param dir_tree table
---@param prefix string Name to concat to form id
---@return NuiTree.Node[]
local function tree_construct_nodes(dir_tree, prefix)
  local files = {}
  local dir_idx = 1 -- index to insert directory
  for k, v in pairs(dir_tree) do
    if k == "." then
      for _, f in ipairs(v) do
        table.insert(
          files,
          NuiTree.Node(f)
        )
      end
    else
      local id = prefix .. "/" .. k
      local children = tree_construct_nodes(v, id)
      local node = NuiTree.Node({ text = k, id = id }, children)
      node:expand()
      table.insert(files, dir_idx, node)
      dir_idx = dir_idx + 1
    end
  end

  return files
end


---@param worktree_status GIT_DELTA
---@param index_status GIT_DELTA
---@param modified boolean
---@return string text_color Text color
---@return string icon_color Icon color
---@return string status_icon Status icon
local function tree_node_colors(worktree_status, index_status, modified)
  local text_color, icon_color = "Fugit2Modifier", "Fugit2Modifier"
  local status_icon = "  "

  if worktree_status == git2.GIT_DELTA.UNTRACKED then
    text_color = "Fugit2Untracked"
    icon_color = "Fugit2Untracked"
    status_icon = " "
  elseif worktree_status == git2.GIT_DELTA.IGNORED
    or index_status == git2.GIT_DELTA.IGNORED then
    text_color = "Fugit2Ignored"
    icon_color = "Fugit2Ignored"
    status_icon = "󰈅 "
  elseif index_status == git2.GIT_DELTA.UNMODIFIED then
    text_color = "Fugit2Unchanged"
    icon_color = "Fugit2Unstaged"
    status_icon = "󰆢 "
  elseif worktree_status == git2.GIT_DELTA.MODIFIED then
    text_color = "Fugit2Modified"
    icon_color = "Fugit2Staged"
    status_icon = "󰱒 "
  else
    text_color = "Fugit2Staged"
    icon_color = "Fugit2Staged"
    status_icon = "󰱒 "
  end

  if modified then
    text_color = "Fugit2Modified"
  end

  return text_color, icon_color, status_icon
end


---@class NuiTreeNodeData
---@field id string
---@field text string
---@field icon string
---@field color string Extmark.
---@field wstatus string Worktree short status.
---@field istatus string Index short status.


---@param item GitStatusItem
---@param bufs table
---@return NuiTreeNodeData
local function tree_node_data_from_item(item, bufs)
  local path = item.path
  local alt_path
  if item.renamed and item.worktree_status == git2.GIT_DELTA.UNMODIFIED then
    path = item.new_path or ""
  end

  local filename = vim.fs.basename(path)
  local extension = vim.filetype.match({ filename = filename })
  local modified = bufs[path] and bufs[path].modified or false

  local icon = WebDevIcons.get_icon(filename, extension, { default = true })
  local wstatus = git2.status_char_dash(item.worktree_status)
  local istatus = git2.status_char_dash(item.index_status)

  local text_color, icon_color, stage_icon = tree_node_colors(item.worktree_status, item.index_status, modified)

  local rename = ""
  if item.renamed and item.index_status == git2.GIT_DELTA.UNMODIFIED then
    rename = " -> " .. utils.make_relative_path(vim.fs.dirname(item.path), item.new_path)
    alt_path = item.new_path
  elseif item.renamed and item.worktree_status == git2.GIT_DELTA.UNMODIFIED then
    rename = " <- " .. utils.make_relative_path(vim.fs.dirname(item.new_path), item.path)
    alt_path = item.path
  end

  local text = filename .. rename

  return {
    id = path,
    alt_path = alt_path,
    text = text,
    icon = icon,
    color = text_color,
    wstatus = wstatus,
    istatus = istatus,
    stage_icon = stage_icon,
    stage_color = icon_color,
    modified = modified
  }
end


---@param node NuiTree.Node
---@return NuiLine
local function tree_prepare_node(node)
  local line = NuiLine()
  line:append(string.rep("  ", node:get_depth() - 1))

  if node:has_children() then
    line:append(node:is_expanded() and "  " or "  ", "Fugit2SymbolicRef")
    line:append(node.text)
  else
    local format_str = "%s %-" .. (48 - node:get_depth() * 2) ..  "s"
    line:append(string.format(format_str, node.icon, node.text), node.color)

    line:append(node.modified and "[+] " or "    ", node.color)
    line:append(node.stage_icon .. " " .. node.wstatus .. node.istatus, node.stage_color)
  end

  return line
end


---@class Fugit2GitStatusTree
---@field bufnr integer
---@field namespace integer
---@field tree NuiTree
local GitStatusTree = Object("Fugit2GitStatusTree")


---@param bufnr integer
---@param namespace integer
function GitStatusTree:init(bufnr, namespace)
  self.bufnr = bufnr
  self.namespace = namespace

  self.tree = NuiTree {
    bufnr = bufnr,
    ns_id = namespace,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
    },
    prepare_node = tree_prepare_node,
    nodes = {}
  }
end


--TODO: remove after having diff
---@return integer files_change
---@return integer files_remove
function GitStatusTree:index_count()
  local files_change, files_remove = 0, 0

  ---@type (string | boolean)[]
  local queue = { false }

  while #queue > 0 do
    local parent = table.remove(queue, 1) or nil
    for _, node in ipairs(self.tree:get_nodes(parent)) do
      if node:has_children() then
        table.insert(queue, node:get_id())
      elseif node.istatus then
        if node.istatus == "D" then
          files_remove = files_remove + 1
        elseif node.istatus ~= "-" and node.istatus ~= "?" then
          files_change = files_change + 1
        end
      end
    end
  end

  return files_change, files_remove
end


---@param status GitStatusItem[]
function GitStatusTree:update(status)
  -- get all bufs modified info
  local bufs = {}
  for _, bufnr in pairs(vim.tbl_filter(vim.api.nvim_buf_is_loaded, vim.api.nvim_list_bufs())) do
    local b = vim.bo[bufnr]
    if b and b.modified then
      local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
      bufs[path] = {
        modified = b.modified
      }
    end
  end

  -- prepare tree
  local dir_tree = {}

  for _, item in ipairs(status) do
    local dirname = vim.fs.dirname(item.path)
    if item.renamed and item.worktree_status == git2.GIT_DELTA.UNMODIFIED then
      dirname = vim.fs.dirname(item.new_path)
    end

    local dir = dir_tree
    if dirname ~= "" and dirname ~= "." then
      for s in vim.gsplit(dirname, "/", { plain = true }) do
        if dir[s] then
          dir = dir[s]
        else
          dir[s] = {}
          dir = dir[s]
        end
      end
    end

    local entry = tree_node_data_from_item(item, bufs)

    if dir["."] then
      table.insert(dir["."], entry)
    else
      dir["."] = { entry }
    end
  end

  self.tree:set_nodes(tree_construct_nodes(dir_tree, ""))
end


-- Adds or unstage a node from index.
---@param repo GitRepository
---@param index GitIndex
---@param node NuiTree.Node
---@return boolean updated Tree is updated or not.
---@return boolean refresh Whether needed to do full refresh.
function GitStatusTree:index_add_reset(repo, index, node)
  local ret
  local updated = false
  local inplace = true -- whether can update status inplace

  if node.alt_path and (node.wstatus == "R" or node.wstatus == "M")  then
    -- rename
    ret = index:add_bypath(node.alt_path)
    if ret ~= 0 then
      error("Git Error when handling rename " .. ret)
    end

    ret = index:remove_bypath(node.id)
    if ret ~= 0 then
      error("Git Error when handling rename " .. ret)
    end

    updated = true
    inplace = false -- requires full refresh
  elseif node.wstatus == "?" or node.wstatus == "T" or node.wstatus == "M"  then
    -- add to index if worktree status is in (UNTRACKED, MODIFIED, TYPECHANGE)
    ret = index:add_bypath(node.id)
    if ret ~= 0 then
      error("Git Error when adding to index: " .. ret)
    end

    updated = true
  elseif node.wstatus == "D" then
    -- remove from index
    ret = index:remove_bypath(node.id)
    if ret ~= 0 then
      error("Git Error when removing from index: " .. ret)
    end

    updated = true
  elseif node.alt_path and (node.istatus == "R" or node.istatus == "M") then
    -- reset both path if rename in index
    ret = repo:reset_default({node.id, node.alt_path})
    if ret ~= 0 then
      error("Git Error when reset rename: " .. ret)
    end

    updated = true
    inplace = false -- requires full refresh
  elseif node.istatus ~= "-" and node.istatus ~= "?" then
    -- else reset if index status is not in (UNCHANGED, UNTRACKED, RENAMED)
    ret = repo:reset_default({node.id})
    if ret ~= 0 then
      error("Git Error when unstage from index: " .. ret)
    end

    updated = true
  end

  -- inplace update
  if updated and inplace then
    local worktree_status, index_status, err = repo:status_file(node.id)
    if err ~= 0 then
      -- try to do full refresh
      inplace = false
    else
      node.wstatus = git2.status_char_dash(worktree_status)
      node.istatus = git2.status_char_dash(index_status)
      node.color, node.stage_color, node.stage_icon = tree_node_colors(
        worktree_status, index_status, node.modified or false
      )
    end
  end

  return updated, not inplace
end


function GitStatusTree:render()
  self.tree:render()
end


-- ==========================
-- |  Commit Message buffer |
-- ==========================

---@enum NuiGitCommitMode
local CommitMode = {
  COMMIT = 1,
  REWORD = 2,
  EXTEND = 3,
  AMEND  = 4,
}

-- ===================
-- | Main git status |
-- ===================

---@enum Fugit2GitStatusSidePanel
local SidePanel = {
  NONE       = 0,
  PATCH_VIEW = 1,
  DIFF_VIEW  = 2
}


---@class Fugit2GitStatusView
---@field info_popup NuiPopup
---@field file_popup NuiPopup
---@field input_popup NuiPopup
---@field repo GitRepository
local GitStatus = Object("Fugit2GitStatusView")


---Inits GitStatus.
---@param ns_id integer
---@param repo GitRepository
---@param last_window integer
function GitStatus:init(ns_id, repo, last_window)
  self.ns_id = -1
  if ns_id then
    self.ns_id = ns_id
  end

  if repo ~= nil then
    self.repo = repo
    local index, sig, err

    index, err = repo:index()
    if index == nil then
      error("libgit2 Error " .. err)
    end
    self.index = index

    sig, err = repo:signature_default()
    if sig then
      self.sign = sig
    end
  else
    error("Null repo")
  end

  -- setup popups
  self.info_popup = NuiPopup {
    ns_id = ns_id,
    enter = false,
    focusable = true,
    border = {
      style = "rounded",
      padding = {
        top = 1,
        bottom = 1,
        left = 2,
        right = 2,
      },
      text = {
        top = " Status ",
        top_align = "left",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
    buf_options = {
      modifiable = true,
      readonly = false,
      swapfile = false,
      buftype  = "nofile",
    },
  }
  self.file_popup = NuiPopup {
    ns_id = ns_id,
    enter = true,
    focusable = true,
    zindex = 50,
    border = {
      style = "rounded",
      padding = {
        top = 0,
        bottom = 0,
        left = 1,
        right = 1,
      },
      text = {
        top = " 󰙅 Files ",
        top_align = "left",
        bottom = NuiText("[c]ommits", "FloatFooter"),
        bottom_align = "right",
      },
    },
    win_options = {
      winblend = 0,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = true,
    },
    buf_options = {
      modifiable = true,
      readonly = false,
      swapfile = false,
      buftype  = "nofile",
    },
  }

  self.input_popup = NuiPopup {
    ns_id = ns_id,
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      padding = {
        left = 1, right = 1
      },
      text = {
        top = NuiText(" Create commit ", "Fugit2MessageHeading"),
        top_align = "left",
        bottom = NuiText("[ctrl-c][esc][q]uit, [ctrl-enter][enter]", "FloatFooter"),
        bottom_align = "right",
      }
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
    buf_options = {
      modifiable = true,
      filetype = "gitcommit",
    }
  }

  -- menus
  local menu_item_align = { text_align = "center" }
  local commit_menu = UI.Menu({
    ns_id = ns_id,
    enter = true,
    position = "50%",
    relative = "editor",
    size = {
      width = 36,
      height = 8,
    },
    zindex = 52,
    border = {
      style = "single",
      text = {
        top = "Commit Menu",
        top_align = "left",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    }
  }, {
    NuiMenu.separator(
    NuiText("Create", "Fugit2MenuHead"),
      menu_item_align
    ),
    NuiMenu.item(NuiLine({NuiText("c ", "Fugit2MenuKey"), NuiText("Commit")}), { id = "c" }),
    NuiMenu.separator(
      NuiLine { NuiText("Edit ", "Fugit2MenuHead"), NuiText("HEAD", "Fugit2Staged") },
      menu_item_align
    ),
    NuiMenu.item(NuiLine { NuiText("e ", "Fugit2MenuKey"), NuiText("Extend") }, { id = "e" }),
    NuiMenu.item(NuiLine { NuiText("w ", "Fugit2MenuKey"), NuiText("Reword") }, { id = "w" }),
    NuiMenu.item(NuiLine { NuiText("a ", "Fugit2MenuKey"), NuiText("Amend") }, { id = "a" }),
    NuiMenu.separator(
      NuiText("View/Edit", "Fugit2MenuHead"),
      menu_item_align
    ),
    NuiMenu.item(NuiLine { NuiText("g ", "Fugit2MenuKey"), NuiText("Graph") }, { id = "g" }),
  })
  local amend_confirm = UI.Confirm(
    self.ns_id,
    NuiLine { NuiText("This commit has already been pushed to upstream, do you really want to modify it?") }
  )

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
  ---@type Fugit2GitStatusTree
  self._tree = GitStatusTree(self.file_popup.bufnr, self.ns_id)

  -- setup layout
  ---@type { [string]: NuiLayout.Box }
  self._boxes = {
    main = NuiLayout.Box({
        NuiLayout.Box(self.info_popup, { size = 6 }),
        NuiLayout.Box(self.file_popup, { grow = 1 }),
      }, { dir = "col" }
    ),
    main_row = NuiLayout.Box(self.file_popup, { grow = 1 })
  }
  self._layout_opts = {
    main = {
      position = "50%",
      size = { width = "60%", height = "60%" }
    },
    diff = {
      position = "50%",
      size = { width = "80%", height = "60%" }
    }
  }
  self._layout = NuiLayout(
    {
      relative = "editor",
      position = "50%",
      size = {
        width = "60%",
        height = "60%",
      },
    },
    self._boxes.main
  )
  self._menus = {
    amend_confirm = amend_confirm,
    commit = commit_menu
  }

  ---@class Fugit2GitStatusGitStates
  ---@field head GitStatusHead?
  ---@field ahead integer
  ---@field behind integer
  ---@field index_updated boolean Whether git status is updated
  ---@field head_tree GitTree
  ---@field unstaged_diff { [string]: GitPatch }
  ---@field staged_diff { [string]: GitPatch }
  self._git = {
    head = nil, ahead = 0, behind = 0,
    index_updated = false,
    unstaged_diff = {}, staged_diff = {},
  }
  -- state variables for UI
  ---@class Fugit2GitStatusInternal
  ---@field last_window integer
  ---@field commit_mode NuiGitCommitMode
  ---@field side_panel Fugit2GitStatusSidePanel
  ---@field last_patch_line integer
  ---@field patch_staged_shown boolean
  ---@field patch_unstaged_shown boolean
  self._states = {
    last_window = last_window,
    commit_mode = CommitMode.COMMIT,
    side_panel  = SidePanel.NONE
  }

  -- keymaps
  self:setup_handlers()

  -- get git content
  self:update()
end

---Inits Diff View popup.
function GitStatus:_init_diff_popups()
  self._diff_head_buffer = vim.api.nvim_create_buf(false, true)
  -- unstaged popup will use external buffer
  self._diff_unstaged = DiffView(self.ns_id, "Unstaged", self._diff_head_buffer)
  self._diff_staged = DiffView(self.ns_id, "Staged")
end

---Inits Patch View popup
function GitStatus:_init_patch_popups()
  self._patch_unstaged = PatchView(self.ns_id, "Unstaged", "Fugit2Unstaged")
  self._patch_staged = PatchView(self.ns_id, "Staged", "Fugit2Staged")
  local opts = { noremap = true, nowait= true }

  local exit_fn = function()
    self:focus_file()
    vim.fn.feedkeys("q")
  end
  self._patch_unstaged:map("n", { "q", "<esc" }, exit_fn, opts)
  self._patch_staged:map("n", { "q", "<esc>" }, exit_fn, opts)

  local states = self._states

  -- [h]: move left
  self._patch_unstaged:map("n", "h", function()
    self:focus_file()
  end, opts)
  self._patch_staged:map("n", "h", function()
    if states.patch_unstaged_shown then self._patch_unstaged:focus()
    else
      self:focus_file()
    end
  end, opts)

  -- [l]: move right
  self._patch_unstaged.popup:map("n", "l", function()
    if states.patch_staged_shown then
      self._patch_staged:focus()
    else
      vim.cmd("normal! l")
    end
  end, opts)

  -- [=]: turn off
  local turn_off_patch_fn = function()
    self:focus_file()
    vim.fn.feedkeys("=")
  end
  self._patch_staged:map("n", "=", turn_off_patch_fn, opts)
  self._patch_unstaged:map("n", "=", turn_off_patch_fn, opts)

  -- [-]: Stage handling
  self._patch_unstaged.popup:map("n", "-", function()
    local diff_str = self._patch_unstaged:get_partial_diff_hunk()
    if not diff_str then
      vim.notify("[Fugit2] Failed to get hunk", vim.log.levels.ERROR)
      return
    end

    local diff, err = git2.Diff.from_buffer(diff_str)
    if not diff then
      vim.notify("[Fugit2] Failed to construct git2 diff, code " .. err, vim.log.levels.ERROR)
      return
    end

    err = self.repo:apply_index(diff)
    if err ~= 0 then
      vim.notify("[Fugit2] Failed to apply diff, code " .. err, vim.log.levels.ERROR)
      return
    end
  end, opts)
end


---Updates git status.
function GitStatus:update()
  local git_status, git_error = git2.status(self.repo)

  for i, _ in ipairs(self._status_lines) do
    self._status_lines[i] = nil
  end

  ---@type NuiLine[]
  local lines = self._status_lines

  if git_status == nil then
    lines = {
      NuiLine { NuiText(string.format("Git2 Error Code: %d", git_error), "Error") }
    }
  else
    -- update status panel
    self._git.head = git_status.head

    local head_line = NuiLine { NuiText("HEAD", "Fugit2Header") }
    if git_status.head.is_detached then
      head_line:append(" (detached)", "Fugit2Heading")
    else
      head_line:append("     ")
    end

    local ahead, behind = 0, 0
    if git_status.upstream then
      ahead, behind = git_status.upstream.ahead, git_status.upstream.behind
      self._git.ahead, self._git.behind = ahead, behind
    end
    local ahead_behind = ahead + behind

    local branch_width = math.max(
      git_status.head.name:len() + (ahead_behind > 0 and 5 or 0),
      git_status.upstream and git_status.upstream.name:len() or 0
    )
    local branch_format = "%s%-" .. branch_width .. "s"

    local author_width = math.max(
      git_status.head.author:len(),
      git_status.upstream and git_status.upstream.author:len() or 0
    )
    local author_format = " %-" .. author_width .. "s"

    local head_icon = utils.get_git_namespace_icon(git_status.head.namespace)
    if ahead_behind == 0 then
      head_line:append(
        string.format(branch_format, head_icon, git_status.head.name),
        "Fugit2SymbolicRef"
      )
    else
      head_line:append(head_icon .. git_status.head.name, "Fugit2SymbolicRef")
      local padding = (
        branch_width
        - git_status.head.name:len()
        - (ahead > 0 and 2 or 0)
        - (behind > 0 and 2 or 0)
      )
      if padding > 0 then
        head_line:append(string.rep(" ", padding))
      end
      local ahead_behind_str = (
        (ahead > 0 and "↑" .. ahead or "")
        .. (behind > 0 and "↓" .. behind or "")
      )
      head_line:append(ahead_behind_str, "Fugit2Count")
    end

    head_line:append(string.format(author_format, git_status.head.author), "Fugit2Author")
    head_line:append(" " .. git_status.head.oid .. " ", "Fugit2ObjectId")
    head_line:append(utils.message_title_prettify(git_status.head.message))
    table.insert(lines, head_line)

    local upstream_line = NuiLine { NuiText("Upstream ", "Fugit2Header") }
    if git_status.upstream then
      self._menus.amend_confirm:set_text(NuiLine {
        NuiText("This commit has already been pushed to "),
        NuiText(git_status.upstream.name, "Fugit2SymbolicRef"),
        NuiText(", do you really want to modify it?")
      })

      local remote_icon = utils.get_git_icon(git_status.upstream.remote_url)

      local upstream_name = string.format(branch_format, remote_icon, git_status.upstream.name)
      if git_status.upstream.ahead > 0 or git_status.upstream.behind > 0 then
        upstream_line:append(upstream_name, "Fugit2SymbolicRef")
      else
        upstream_line:append(upstream_name, "Fugit2Staged")
      end

      upstream_line:append(string.format(author_format, git_status.upstream.author), "Fugit2Author")
      upstream_line:append(" " .. git_status.upstream.oid .. " ", "Fugit2ObjectId")

      upstream_line:append(utils.message_title_prettify(git_status.upstream.message))
    else
      upstream_line:append("?", "Fugit2SymbolicRef")
    end
    table.insert(lines, upstream_line)

    -- update files tree
    self._tree:update(git_status.status)

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
  end
end


-- Renders git status
function GitStatus:render()
  for i, line in ipairs(self._status_lines) do
    line:render(self.info_popup.bufnr, self.ns_id, i)
  end

  self._tree:render()
end


function GitStatus:mount()
  self._layout:mount()
end


function GitStatus:write_index()
  if self._git.index_updated then
    if self.index:write() == 0 then
      self._git.index_updated = false
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
  vim.api.nvim_set_current_win(self.file_popup.winid)
end

---@param back_to_main boolean
function GitStatus:off_input(back_to_main)
  vim.api.nvim_buf_set_lines(
    self.input_popup.bufnr,
    0, -1, true, {}
  )
  if back_to_main then
    self._layout:update(self._layout_opts.main, self._boxes.main)
  else
    self._layout:update(NuiLayout.Box(
      {
        NuiLayout.Box(self.info_popup, { size = 6 }),
        NuiLayout.Box(self._boxes.main_row, { dir = "row", grow = 1 }),
      },
      { dir = "col" }
    ))
  end

  vim.api.nvim_set_current_win(self.file_popup.winid)
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


---Makes a commit
---@param message string
function GitStatus:commit(message)
  local prettified = check_signature_message(self.sign, message)

  if self.sign and prettified then
    self:write_index()
    local commit_id, err = self.repo:commit(self.index, self.sign, prettified)
    if commit_id then
      vim.notify("New commit " .. commit_id:tostring(8), vim.log.levels.INFO)
      self:off_input(true)
      self:update()
      self:render()
    else
      vim.notify("Failed to create commit, code: " .. err, vim.log.levels.ERROR)
    end
  end
end


---Extends HEAD commit
---add files in index to HEAD commit
function GitStatus:commit_extend()
  self:write_index()
  local commit_id, err = self.repo:amend_extend(self.index)
  if commit_id then
    vim.notify("Extend HEAD " .. commit_id:tostring(8), vim.log.levels.INFO)
    self:update()
    self:render()
  else
    vim.notify("Failed to extend HEAD, code: " .. err, vim.log.levels.ERROR)
  end
end


---Reword HEAD commit
---change commit message of HEAD commit
---@param message string commit message
function GitStatus:commit_reword(message)
  local prettified = check_signature_message(self.sign, message)

  if self.sign and prettified then
    local commit_id, err = self.repo:amend_reword(self.sign, prettified)
    if commit_id then
      vim.notify("Reword HEAD " .. commit_id:tostring(8), vim.log.levels.INFO)
      self:off_input(false)
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
function GitStatus:commit_amend(message)
  local prettified = check_signature_message(self.sign, message)
  if self.sign and prettified then
    self:write_index()
    local commit_id, err = self.repo:amend(self.index, self.sign, prettified)
    if commit_id then
      vim.notify("Amend HEAD " .. commit_id:tostring(8), vim.log.levels.INFO)
      self:off_input(true)
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
  local change, remove = 0, 0
  if include_changes then
    change, remove = self._tree:index_count()
    if notify_empty and change + remove < 1 then
      vim.notify("Empty commit!", vim.log.levels.WARN)
    end
  end

  local title = string.format(
    " %s - %s%s%s",
    init_str, tostring(self.sign),
    change > 0  and "+" .. change or "",
    remove > 0 and "-" .. remove or ""
  )
  self.input_popup.border:set_text(
    "top",
    NuiText(title, "Fugit2MessageHeading"),
    "left"
  )
end


---@return fun()
function GitStatus:commit_commit_handler()
  return function()
    self._states.commit_mode = CommitMode.COMMIT

    self:_set_input_popup_commit_title("Create commit", true, true)

    self:focus_input()
    vim.cmd.startinsert()
  end
end


---@return fun()
function GitStatus:commit_extend_handler()
  return function()
    self._states.commit_mode = CommitMode.EXTEND

    if self._git.ahead == 0 then
      self._menus.amend_confirm:show()
      return
    end

    self:commit_extend()
  end
end


---@param is_reword boolean reword only mode
---@return fun()
function GitStatus:commit_amend_handler(is_reword)
  return function()
    self._states.commit_mode = is_reword and CommitMode.REWORD or CommitMode.AMEND

    if self._git.ahead == 0 then
      self._menus.amend_confirm:show()
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
end

function GitStatus:amend_confirm_yes_handler()
  return function()
    local mode = self._states.commit_mode
    if mode == CommitMode.EXTEND then
      self:commit_extend()
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

---@return NuiTree.Node?
---@return integer? linenr
function GitStatus:get_child_node_linenr()
  local node, linenr, _ = self._tree.tree:get_node() -- get current node

  -- depth first search to get first child
  while node and node:has_children() do
    local children = node:get_child_ids()
    node, linenr, _ = self._tree.tree:get_node(children[1])
  end

  return node, linenr
end

---Updates patch info based on node
---@param node NuiTree.Node
---@return boolean unstaged_updated
---@return boolean staged_updated
function GitStatus:update_patch(node)
  local unstaged_updated, staged_updated = false, false

  -- init in the first update
  if not self._patch_staged or not self._patch_unstaged then
    self:_init_patch_popups()
  end

  if node.id then
    local diff, patches, err, found
    local paths = { node.id, node.alt_path }

    found = self._git.unstaged_diff[node.id]
    if node.wstatus ~= "-" and not found then
      diff, err = self.repo:diff_index_to_workdir(self.index, paths)
      if not diff then
        vim.notify("Failed to get unstaged diff " .. err, vim.logs.levels.ERROR)
        goto git_status_update_patch_index
      end
      patches, err = diff:patches(false)
      if #patches == 0 then
        vim.notify("Failed to get unstage patch " .. err, vim.logs.levels.ERROR)
        goto git_status_update_patch_index
      end
      self._git.unstaged_diff[node.id] = patches[1]
      found = patches[1]
    end

    if found then
      self._patch_unstaged:update(found)
      unstaged_updated = true
    end

    ::git_status_update_patch_index::
    found = self._git.staged_diff[node.id]
    if node.istatus ~= "-" and node.istatus ~= "?" and not found then
      diff, err = self.repo:diff_head_to_index(self.index, paths)
      if not diff then
        vim.notify("Failed to get unstaged diff " .. err, vim.logs.levels.ERROR)
        goto git_status_update_patch_end
      end
      patches, err = diff:patches(false)
      if #patches == 0 then
        vim.notify("Failed to get unstage patch " .. err, vim.logs.levels.ERROR)
        goto git_status_update_patch_end
      end
      self._git.staged_diff[node.id] = patches[1]
      found = patches[1]
    end

    if found then
      self._patch_staged:update(found)
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
        NuiLayout.Box(self.file_popup, { size = 60 }),
        NuiLayout.Box(self._patch_unstaged.popup, { grow = 1 }),
        NuiLayout.Box(self._patch_staged.popup, { grow = 1 })
      })
    end
  elseif unstaged then
    row = self._boxes.patch_unstaged
    if not row then
      row = utils.update_table(self._boxes, "patch_unstaged", {
        NuiLayout.Box(self.file_popup, { size = 60 }),
        NuiLayout.Box(self._patch_unstaged.popup, { grow = 1 }),
      })
    end
  else
    row = self._boxes.patch_staged
    if not row then
      row = utils.update_table(self._boxes, "patch_staged", {
        NuiLayout.Box(self.file_popup, { size = 60 }),
        NuiLayout.Box(self._patch_staged.popup, { grow = 1 })
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
  self._main_row = NuiLayout.Box(self.file_popup, { grow = 1 })
  self._states.side_panel = SidePanel.NONE
end

---Update diff view info based on node
---@param node NuiTree.Node
---@return boolean unstaged_updated
---@return boolean staged_updated
function GitStatus:update_diff_views(node)
  -- init before update
  if not self._diff_staged then
    self:_init_diff_popups()
  end

  if not node.id then
    return false, false
  end

  local blob, entry, err
  local unstaged_updated, staged_updated = false, false

  if node.wstatus ~= "-" then
    unstaged_updated = true
  end

  -- file for staged
  if node.istatus ~= "?" then
    entry = self.index:get_bypath(node.id, git2.GIT_INDEX_STAGE.NORMAL)
    if entry then
      blob, err = self.repo:blob_lookup(entry.id)
      if not blob then
        vim.notify(
          string.format("[Fugit2] Can't retrieve %s from index, code: %d", node.id, err),
          vim.log.levels.ERROR
        )
        goto git_status_update_diff_views_head_file
      end

      staged_updated = true
      vim.api.nvim_buf_set_lines(
        self._diff_staged:bufnr(), 0, -1, true,
        vim.split(blob:content(), "\n", { plain = true, trimempty = true })
      )
    end
  end

  -- file for head
  ::git_status_update_diff_views_head_file::
  if not self._git.head_tree then
    local tree
    tree, err = self.repo:head_tree()
    if err == git2.GIT_ERROR.GIT_EUNBORNBRANCH or err == git2.GIT_ERROR.GIT_ENOTFOUND then
      vim.api.nvim_buf_set_lines(self._diff_head_buffer, 0, -1, true, {})
      goto git_status_update_diff_views_end
    end
    if not tree then
      vim.notify("[Fugit2] Can't get head tree, code " .. err, vim.log.levels.ERROR)
      goto git_status_update_diff_views_end
    end
    self._git.head_tree = tree
  end

  entry, err = self._git.head_tree:entry_bypath(node.id)
  if not entry then
    vim.notify("[Fugit2] Can't find blob in HEAD, code " .. err, vim.log.levels.ERROR)
    goto git_status_update_diff_views_end
  end

  blob, err = self.repo:blob_lookup(entry:id())
  if not blob then
    vim.notify("[Fugit2] Can't retrieve blob in HEAD, code " .. err, vim.log.levels.ERROR)
    goto git_status_update_diff_views_end
  end

  vim.api.nvim_buf_set_lines(
    self._diff_head_buffer, 0, -1, true,
    vim.split(blob:content(), "\n", { plain = true, trimempty = true })
  )

  ::git_status_update_diff_views_end::
  return unstaged_updated, staged_updated
end

---Show and setup diff view
---@param unstaged boolean
---@param staged boolean
function GitStatus:show_diff_views(unstaged, staged)
  if not unstaged and not staged then
    return
  end

  local row
  if unstaged and staged then
    row = self._boxes.diff_unstaged_staged
    if not row then
      row = utils.update_table(self._boxes, "diff_unstaged_staged", {
        NuiLayout.Box(self.file_popup, { size = 60 }),
        NuiLayout.Box(self._diff_unstaged.popup, { grow = 1 }),
        NuiLayout.Box(self._diff_staged.popup, { grow = 1 })
      })
    end
  elseif unstaged then
    row = self._boxes.diff_unstaged
    if not row then
      row = utils.update_table(self._boxes, "diff_unstaged", {
        NuiLayout.Box(self.file_popup, { size = 60 }),
        NuiLayout.Box(self._diff_unstaged.popup, { grow = 1 }),
      })
    end
  else
    row = self._boxes.diff_staged
    if not row then
      row = utils.update_table(self._boxes, "diff_staged", {
        NuiLayout.Box(self.file_popup, { size = 60 }),
        NuiLayout.Box(self._diff_staged.popup, { grow = 1 })
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
  self._states.side_panel = SidePanel.DIFF_VIEW
end

---@param file string
function GitStatus:setup_diff_views(file)
  -- update file for unstaged diff buffer
  local file_bufnr
  for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr)
      and vim.api.nvim_buf_get_name(bufnr) == file
    then
      file_bufnr = bufnr
      break
    end
  end

  -- Unstaged File panel
  vim.cmd.diffoff({ bang = true })
  vim.api.nvim_set_current_win(self._diff_unstaged:winid())
  if file_bufnr then
    self._diff_unstaged:set_bufnr(file_bufnr)
  else
    vim.cmd.edit(vim.fn.fnameescape(file))
    file_bufnr = vim.api.nvim_get_current_buf()
  end
  vim.cmd.diffthis()

  -- Index file panel
  vim.api.nvim_set_current_win(self._diff_staged.popup.winid)
  vim.cmd.diffthis()

  -- Head Scratch panel
  vim.api.nvim_set_current_win(self._diff_unstaged:winid())
  vim.api.nvim_set_current_buf(self._diff_head_buffer)
  vim.cmd.diffthis()
  vim.api.nvim_set_current_buf(file_bufnr)
  self._diff_unstaged:set_bufnr(file_bufnr)
  vim.fn.feedkeys("zM")
  vim.fn.feedkeys("gg")

end


-- Setup keymap and event handlers
function GitStatus:setup_handlers()
  local map_options = { noremap = true, nowait = true }
  local tree = self._tree
  local states = self._states
  local git = self._git

  local exit_fn = function()
    self:write_index()
    if self._patch_unstaged then
      self._patch_unstaged:unmount()
      self._patch_unstaged = nil
    end
    if self._patch_staged then
      self._patch_staged:unmount()
      self._patch_staged = nil
    end
    if self._diff_unstaged then
      self._diff_unstaged:unmount()
      self._diff_unstaged = nil
    end
    if self._diff_staged then
      self._diff_staged:unmount()
      self._diff_staged = nil
    end
    if self._diff_head_buffer then
      vim.cmd.bdelete(tostring(self._diff_head_buffer))
    end
    self._menus.amend_confirm:unmount()
    self._menus.commit:unmount()
    self._layout:unmount()

    vim.api.nvim_set_current_win(states.last_window)
  end

  -- exit
  self.file_popup:map("n", {"q", "<esc>"}, exit_fn, map_options)
  self.file_popup:map("i", "q", exit_fn, map_options)
  -- popup:on(event.BufLeave, exit_fn)

  -- refresh
  self.file_popup:map("n", "r",
    function ()
      self:update()
      tree:render()
    end,
    map_options
  )

  -- collapse
  self.file_popup:map("n", "h",
    function()
      local node = tree.tree:get_node()

      if node and node:collapse() then
        tree:render()
      end
    end,
    map_options
  )

  -- collapse all
  self.file_popup:map("n", "H",
    function()
      local updated = false

      for _, node in pairs(tree.tree.nodes.by_id) do
        updated = node:collapse() or updated
      end

      if updated then
        tree:render()
      end
    end,
    map_options
  )

  -- Expand and move right
  self.file_popup:map("n", "l", function()
    local node = tree.tree:get_node()
    if node then
      if node:expand() then
        tree:render()
      end
      if not node:has_children() and states.side_panel == SidePanel.PATCH_VIEW then
        if states.patch_unstaged_shown then
          self._patch_unstaged:focus()
        elseif states.patch_staged_shown then
          self._patch_staged:focus()
        end
      end
    end
  end, map_options
  )

  -- expand all
  self.file_popup:map("n", "L",
    function()
      local updated = false

      for _, node in pairs(tree.tree.nodes.by_id) do
        updated = node:expand() or updated
      end

      if updated then
        tree:render()
      end
    end,
    map_options
  )

  -- Diff view & move cursor
  states.last_patch_line = -1
  states.patch_staged_shown = false
  states.patch_unstaged_shown = false

  self.file_popup:on(event.CursorMoved, function()
    if states.side_panel == SidePanel.PATCH_VIEW then
      local node, linenr = self:get_child_node_linenr()
      if node and linenr and linenr ~= states.last_patch_line then
        states.patch_unstaged_shown, states.patch_staged_shown = self:update_patch(node)
        if states.patch_unstaged_shown or states.patch_staged_shown then
          self:show_patch_view(states.patch_unstaged_shown, states.patch_staged_shown)
          states.last_patch_line = linenr
        end
      end
    end
  end)

  ---- Turn on/off patch view
  self.file_popup:map("n", "=", function()
    if states.side_panel == SidePanel.PATCH_VIEW then
      self:hide_patch_view()
    elseif states.side_panel == SidePanel.NONE then
      local node, linenr = self:get_child_node_linenr()
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
  self.file_popup:map("n", "<cr>", function ()
    local node = tree.tree:get_node()
    if node and node:has_children() then
      if node:is_expanded() then
        node:collapse()
      else
        node:expand()
      end
      tree:render()
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
  local add_reset_fn = function()
    local node, linenr = tree.tree:get_node()
    if not node or node:has_children() then
      return
    end

    local updated, refresh = tree:index_add_reset(self.repo, self.index, node)
    if not updated then
      return
    end

    if refresh then
      self:update()
    end
    tree:render()

    git.index_updated = true

    node, linenr = tree.tree:get_node()
    if node and linenr then
      -- remove cached diff
      git.staged_diff[node.id] = nil
      git.unstaged_diff[node.id] = nil

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
  self.file_popup:map("n", { "-", "<space>" }, add_reset_fn, map_options)

  ---- Write index
  self.file_popup:map("n", "w",
    function ()
      if self.index:write() == 0 then
        vim.notify("[Fugit2] Index saved", vim.log.levels.INFO)
      end
    end,
    map_options
  )

  -- Diff view

  ---- turn on diffview
  self.file_popup:map("n", "dd", function()
    if states.side_panel == SidePanel.PATCH_VIEW then
      self:hide_patch_view()
    end

    if states.side_panel == SidePanel.NONE then
      local node, linenr = self:get_child_node_linenr()
      if node and linenr then
        local unstaged_show, staged_show = self:update_diff_views(node)
        self:show_diff_views(true, true) -- show both panel
        self:setup_diff_views(node.id)
        -- self:show_diff_views(unstaged_show, staged_show)
      end
    end
  end, map_options)

  ---- turn off diffview
  self.file_popup:map("n", "dq", function()
  end, map_options)

  ---- Commit menu
  local commit_commit_fn = self:commit_commit_handler()
  local commit_extend_fn = self:commit_extend_handler()
  local commit_reword_fn = self:commit_amend_handler(true)
  local commit_amend_fn = self:commit_amend_handler(false)

  local commit_graph_fn = function()
    self._menus.commit:unmount()
    exit_fn()
    require("fugit2.view.ui").new_fugit2_graph_window(self.ns_id, self.repo):mount()
  end

  self._menus.commit:on_submit(function(item_id)
    if item_id == "c" then
      commit_commit_fn()
    elseif item_id == "e" then
      commit_extend_fn()
    elseif item_id == "w" then
      commit_reword_fn()
    elseif item_id == "a" then
      commit_amend_fn()
    elseif item_id == "g" then
      commit_graph_fn()
    end
  end)

  self.file_popup:map("n", "c", function ()
    self._menus.commit:mount()
  end, map_options)

  -- Amend confirm
  self._menus.amend_confirm:on_yes(self:amend_confirm_yes_handler())

  -- Message input
  self.input_popup:map("n", { "q", "<esc>" }, function()
    self:off_input()
  end, map_options)

  self.input_popup:map("i", "<c-c>", function()
    vim.cmd.stopinsert()
    self:off_input()
  end, map_options)

  local input_enter_fn = function()
    local message = vim.trim(table.concat(
      vim.api.nvim_buf_get_lines(self.input_popup.bufnr, 0, -1, true),
      "\n"
    ))
    if states.commit_mode == CommitMode.COMMIT then
      self:commit(message)
    elseif states.commit_mode == CommitMode.REWORD then
      self:commit_reword(message)
    elseif states.commit_mode == CommitMode.AMEND then
      self:commit_amend(message)
    end
  end
  self.input_popup:map("n", "<cr>", input_enter_fn, map_options)
  self.input_popup:map("i", "<c-cr>", function ()
    vim.cmd.stopinsert()
    input_enter_fn()
  end, map_options)
end


return GitStatus
