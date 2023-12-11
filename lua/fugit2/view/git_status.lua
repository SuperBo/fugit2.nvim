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
    print(vim.fs.dirname(item.new_path), item.path)
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


---@class Fugit2GitStatusView
---@field info_popup NuiPopup
---@field file_popup NuiPopup
---@field input_popup NuiPopup
---@field repo GitRepository
local GitStatus = Object("Fugit2GitStatusView")


---Inits GitStatus.
---@param ns_id integer
---@param repo GitRepository
---param commit_menu Fugit2UIMenu
function GitStatus:init(ns_id, repo)
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
    },
  }
  self.file_popup = NuiPopup {
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
    },
  }

  self.input_popup = NuiPopup {
    enter = false,
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
  self._boxes = {
    main = NuiLayout.Box({
        NuiLayout.Box(self.info_popup, { size = 6 }),
        NuiLayout.Box(self.file_popup, { grow = 1 }),
      }, { dir = "col" }
    ),
    input = NuiLayout.Box({
        NuiLayout.Box(self.info_popup, { size = 6 }),
        NuiLayout.Box(self.input_popup, { size = 6 }),
        NuiLayout.Box(self.file_popup, { grow = 1 }),
      }, { dir = "col" }
    ),
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

  -- setup menu
  self._commit_mode = CommitMode.COMMIT
  ---@type {}
  self._git = {
    head = nil, ahead = 0, behind = 0,
    unstaged_diff = {}, staged_diff = {},
  }

  -- This commit has already been published to origin/dev, do you really want to modify it?

  -- keymaps
  self:setup_handlers()

  -- get git content
  self:update()

  -- Whether git status is updated
  self._updated = false
end


-- Updates git status.
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
  if self._updated then
    if self.index:write() == 0 then
      self._updated = false
    end
  end
end


function GitStatus:focus_input()
  self._layout:update(self._boxes.input)
  vim.api.nvim_set_current_win(self.input_popup.winid)
end


function GitStatus:off_input()
  vim.api.nvim_buf_set_lines(
    self.input_popup.bufnr,
    0, -1, true, {}
  )
  self._layout:update(self._boxes.main)
  vim.api.nvim_set_current_win(self.file_popup.winid)
  vim.cmd("stopinsert")
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
      self:off_input()
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
    self:off_input()
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
      self:off_input()
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
      self:off_input()
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
    self._commit_mode = CommitMode.COMMIT

    self:_set_input_popup_commit_title("Create commit", true, true)

    self:focus_input()
    vim.cmd("startinsert")
  end
end


---@return fun()
function GitStatus:commit_extend_handler()
  return function()
    self._commit_mode = CommitMode.EXTEND

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
    self._commit_mode = is_reword and CommitMode.REWORD or CommitMode.AMEND

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
    if self._commit_mode == CommitMode.EXTEND then
      self:commit_extend()
    elseif self._commit_mode == CommitMode.REWORD or self._commit_mode == CommitMode.AMEND then
      if self._commit_mode == CommitMode.REWORD then
        self:_set_input_popup_commit_title("Reword HEAD", false, false)
      else
        self:_set_input_popup_commit_title("Amend HEAD", true, false)
      end

      self:insert_head_message_to_input()
      self:focus_input()
    end
  end
end

function GitStatus:_init_diff_index_to_workdir()
  if not self._diff_index_to_workdir then
    self._diff_index_to_workdir = PatchView(" Workdir ")
    self._boxes.diff_index_to_workdir = NuiLayout.Box({
      NuiLayout.Box(self.info_popup, { size = 6 }),
      NuiLayout.Box({
        NuiLayout.Box(self.file_popup, { size = 30 }),
        NuiLayout.Box(self._diff_index_to_workdir, { grow = 1 })
      }, { dir = "row", grow = 1 })
    }, { dir = "col" })
  end
end

---Updates diff based on current node
---@return GIT_ERROR
function GitStatus:update_diff()
  local node = self._tree.tree:get_node() -- get current node
  -- depth first search to get first child
  while node and node:has_children() do
    local children = node:get_child_ids()
    node = self._tree.tree:get_node(children[1])
  end

  if node and node.id then
    local diff, patches, unstage_patch, staged_patch, err
    local paths = { node.id, node.alt_path }

    if node.wstatus ~= "-" and not self._git.unstaged_diff[node.id] then
      diff, err = self.repo:diff_index_to_workdir(self.index, paths)
      if not diff then
        vim.notify("Failed to get unstaged diff " .. err, vim.logs.levels.ERROR)
        return err
      end
      patches, err = diff:patches(false)
      if err ~= 0 then
        vim.notify("Failed to get unstage patch " .. err, vim.logs.levels.ERROR)
        return err
      end
      self._git.unstaged_diff[node.id] = patches[1]
    end

    if node.istatus ~= "-" and not self._git.staged_diff[node.id] then
      diff, err = self.repo:diff_head_to_index(self.index, paths)
      if not diff then
        vim.notify("Failed to get unstaged diff " .. err, vim.logs.levels.ERROR)
        return err
      end
      patches, err = diff:patches(false)
      if err ~= 0 then
        vim.notify("Failed to get unstage patch " .. err, vim.logs.levels.ERROR)
        return err
      end
      self._git.staged_diff[node.id] = patches[1]
    end

    print(node.id)
    self._diff_unstaged:update(self._git.unstaged_diff[node.id])
    --TODO same thing for diff_staged
  end

  return 0
end

function GitStatus:show_diff()
  local box = self._boxes.diff_unstaged
  if not box then
    self._diff_unstaged = PatchView(" Unstaged ")
    box = NuiLayout.Box({
      NuiLayout.Box(self.info_popup, { size = 6 }),
      NuiLayout.Box({
        NuiLayout.Box(self.file_popup, { size = 60 }),
        NuiLayout.Box(self._diff_unstaged.popup, { grow = 1 })
      }, { dir = "row", grow = 1 })
    }, { dir = "col" })
    self._boxes.diff_unstaged = box
  end
  self._layout:update({
    position = "50%",
    size = { width = "80%", height = "60%" }
  }, box)
end

function GitStatus:hide_diff()
  self._layout:update({
    position = "50%",
    size = { width = "60%", height = "60%" }
  }, self._boxes.main)
end

---@return fun()
function GitStatus:diff_toggle_handler()
  return function()
    if self._diff_showned then
      self:hide_diff()
      self._diff_showned = false
    else
      self:show_diff()
      self._diff_showned = true
      self:update_diff()
    end
  end
end


-- Setup keymap and event handlers
function GitStatus:setup_handlers()
  local map_options = { noremap = true, nowait = true }
  local tree = self._tree

  local exit_fn = function()
    self:write_index()
    self._menus.amend_confirm:unmount()
    self._menus.commit:unmount()
    self._layout:unmount()
  end

  -- exit
  self.file_popup:map("n", "q", exit_fn, map_options)
  self.file_popup:map("i", "q", exit_fn, map_options)
  self.file_popup:map("n", "<esc>", exit_fn, map_options)
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

  -- expand
  self.file_popup:map("n", "l",
    function()
      local node = tree.tree:get_node()

      if node and node:expand() then
        tree:render()
      end
    end,
    map_options
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

  -- collapse expand toggle
  self.file_popup:map("n", "<cr>",
    function ()
      local node = tree.tree:get_node()

      if node and node:has_children() then
        if node:is_expanded() then
          node:collapse()
        else
          node:expand()
        end
        tree:render()
      end
    end,
    map_options
  )

  -- add to index
  local add_reset_fn = function()
    local node = tree.tree:get_node()
    if node and not node:has_children() then
      local updated, refresh = tree:index_add_reset(self.repo, self.index, node)
      if updated then
        if refresh then
          self:update()
        end
        self._updated = true
        tree:render()
      end
    end
  end
  self.file_popup:map("n", "-", add_reset_fn, map_options)
  self.file_popup:map("n", "<space>", add_reset_fn, map_options)

  self.file_popup:map("n", "w",
    function ()
      if self.index:write() == 0 then
        vim.notify("[Fugit2] Index saved", vim.log.levels.INFO)
      end
    end,
    map_options
  )

  -- diff view
  self.file_popup:map("n", "=", self:diff_toggle_handler(), map_options)

  -- move cursor
  local last_line = 1
  self.file_popup:on(event.CursorMoved, function()
    if self._diff_showned then
      local cursor = vim.api.nvim_win_get_cursor(self.file_popup.winid)
      if cursor[1] ~= last_line then
        if self:update_diff() == 0 then
          last_line = cursor[1]
        end
      end
    end
  end)

  -- Commit menu
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
  local input_quit_fn = function()
    self:off_input()
  end

  self.input_popup:map("i", "<c-c>", input_quit_fn, map_options)
  self.input_popup:map("n", "q", input_quit_fn, map_options)
  self.input_popup:map("n", "<esc>", input_quit_fn, map_options)

  local input_enter_handler = function()
    local message = table.concat(
      vim.api.nvim_buf_get_lines(self.input_popup.bufnr, 0, -1, true),
      "\n"
    )
    if self._commit_mode == CommitMode.COMMIT then
      self:commit(message)
    elseif self._commit_mode == CommitMode.REWORD then
      self:commit_reword(message)
    elseif self._commit_mode == CommitMode.AMEND then
      self:commit_amend(message)
    end
  end
  self.input_popup:map("n", "<cr>", input_enter_handler, map_options)
  self.input_popup:map("i", "<c-cr>", input_enter_handler, map_options)
end


return GitStatus
