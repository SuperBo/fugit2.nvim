-- NUI Git helper module

local WebDevIcons = require "nvim-web-devicons"
local NuiLayout = require "nui.layout"
local NuiLine = require "nui.line"
local NuiText = require "nui.text"
local NuiTree = require "nui.tree"
local Object = require "nui.object"

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


---@param worktree_status GIT_STATUS_SHORT
---@param index_status GIT_STATUS_SHORT
---@param modified boolean
---@return string text_color Text color
---@return string icon_color Icon color
---@return string status_icon Status icon
local function tree_node_colors(worktree_status, index_status, modified)
  local text_color, icon_color = "Fugit2Modifier", "Fugit2Modifier"
  local status_icon = "  "

  if worktree_status == git2.GIT_STATUS_SHORT.UNTRACKED then
    text_color = "Fugit2Untracked"
    icon_color = "Fugit2Untracked"
    status_icon = " "
  elseif worktree_status == git2.GIT_STATUS_SHORT.IGNORED
    or index_status == git2.GIT_STATUS_SHORT.IGNORED then
    text_color = "Fugit2Ignored"
    icon_color = "Fugit2Ignored"
    status_icon = "󰈅 "
  elseif index_status == git2.GIT_STATUS_SHORT.UNCHANGED then
    text_color = "Fugit2Unchanged"
    icon_color = "Fugit2Unstaged"
    status_icon = "󰆢 "
  elseif worktree_status == git2.GIT_STATUS_SHORT.MODIFIED then
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
  if item.renamed and item.worktree_status == git2.GIT_STATUS_SHORT.UNCHANGED then
    path = item.new_path or ""
  end

  local filename = vim.fs.basename(path)
  local extension = vim.filetype.match({ filename = filename })
  local modified = bufs[path] and bufs[path].modified or false

  local icon = WebDevIcons.get_icon(filename, extension, { default = true })
  local wstatus = git2.GIT_STATUS_SHORT.toshort(item.worktree_status)
  local istatus = git2.GIT_STATUS_SHORT.toshort(item.index_status)

  local text_color, icon_color, stage_icon = tree_node_colors(item.worktree_status, item.index_status, modified)

  local rename = ""
  if item.renamed and item.index_status == git2.GIT_STATUS_SHORT.UNCHANGED then
    rename = " -> " .. utils.make_relative_path(vim.fs.dirname(item.path), item.new_path)
    alt_path = item.new_path
  elseif item.renamed and item.worktree_status == git2.GIT_STATUS_SHORT.UNCHANGED then
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


---@class NuiGitStatusTree
---@field bufnr integer
---@field namespace integer
---@field tree NuiTree
local NuiGitStatusTree = Object("NuiGitStatusTree")


---@param bufnr integer
---@param namespace integer
function NuiGitStatusTree:init(bufnr, namespace)
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


---@param status GitStatusItem[]
function NuiGitStatusTree:update(status)
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
    if item.renamed and item.worktree_status == git2.GIT_STATUS_SHORT.UNCHANGED then
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
function NuiGitStatusTree:index_add_reset(repo, index, node)
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
      node.wstatus = git2.GIT_STATUS_SHORT.toshort(worktree_status)
      node.istatus = git2.GIT_STATUS_SHORT.toshort(index_status)
      node.color, node.stage_color, node.stage_icon = tree_node_colors(
        worktree_status, index_status, node.modified or false
      )
    end
  end

  return updated, not inplace
end


function NuiGitStatusTree:render()
  self.tree:render()
end


-- ==========================
-- |  Commit Message buffer |
-- ==========================


-- ===================
-- | Main git status |
-- ===================


---@class NuiGitStatus
---@field info_popup NuiPopup
---@field file_popup NuiPopup
---@field input_popup NuiPopup
---@field repo GitRepository
local NuiGitStatus = Object("NuiGitStatus")


-- Inits NuiGitStatus.
---@param info_popup NuiPopup
---@param file_popup NuiPopup
---@param input_popup NuiPopup
---@param namespace integer
---@param repo GitRepository
function NuiGitStatus:init(info_popup, file_popup, input_popup, namespace, repo)
  self.info_popup = info_popup
  self.file_popup = file_popup
  self.input_popup = input_popup

  self.namespace = -1
  if namespace then
    self.namespace = namespace
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
      self.author = tostring(sig)
    end
  else
    error("Null repo")
  end

  ---@type NuiLine[]
  self._status_lines = {}
  ---@type NuiGitStatusTree
  self._tree = NuiGitStatusTree(self.file_popup.bufnr, self.namespace)

  -- setup layout
  self._org_box = NuiLayout.Box({
    NuiLayout.Box(info_popup, { size = 6 }),
    NuiLayout.Box(file_popup, { grow = 1 }),
  }, { dir = "col" })
  self._input_box = NuiLayout.Box({
    NuiLayout.Box(info_popup, { size = 6 }),
    NuiLayout.Box(input_popup, { size = 6 }),
    NuiLayout.Box(file_popup, { grow = 1 }),
  }, { dir = "col" })
  self._layout =  NuiLayout(
    {
      relative = "editor",
      position = "50%",
      size = {
        width = "80%",
        height = "60%",
      },
    },
    self._org_box
  )

  -- keymaps
  self:setup_handlers()

  -- get git content
  self:update()

  -- Whether git status is updated
  self._updated = false
end


-- Updates git status.
function NuiGitStatus:update()
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
    local head_line = NuiLine { NuiText("HEAD", "Fugit2Header") }
    if git_status.head.is_detached then
      head_line:append(" (detached)", "Fugit2Heading")
    end
    head_line:append(": ", "Fugit2Header")

    local head_icon = utils.get_git_namespace_icon(git_status.head.namespace)
    head_line:append(head_icon .. git_status.head.name, "Fugit2SymbolicRef" )
    head_line:append(" " .. git_status.head.oid .. " ", "Fugit2ObjectId")
    head_line:append(utils.lines_head(git_status.head.message))
    table.insert(lines, head_line)

    local upstream_line = NuiLine { NuiText("Upstream: ", "Fugit2Header") }
    if git_status.upstream then
      local remote_icon = utils.get_git_icon(git_status.upstream.remote_url)

      if git_status.upstream.ahead > 0 or git_status.upstream.behind > 0 then
        upstream_line:append(remote_icon .. git_status.upstream.name, "Fugit2SymbolicRef")
      else
        upstream_line:append(remote_icon .. git_status.upstream.name, "Fugit2Staged")
      end

      upstream_line:append(" " .. git_status.upstream.oid .. " ", "Fugit2ObjectId")

      if git_status.upstream.ahead > 0 then
        upstream_line:append(string.format("↑%d ", git_status.upstream.ahead), "Fugit2Count")
      end
      if git_status.upstream.behind > 0 then
        upstream_line:append(string.format("↓%d ", git_status.upstream.behind), "Fugit2Count")
      end

      upstream_line:append(utils.lines_head(git_status.upstream.message))
    else
      upstream_line:append("?", "Fugit2SymbolicRef")
    end
    table.insert(lines, upstream_line)

    self._tree:update(git_status.status)
  end
end


-- Renders git status
function NuiGitStatus:render()
  for i, line in ipairs(self._status_lines) do
    line:render(self.info_popup.bufnr, self.namespace, i)
  end

  self._tree:render()
end


function NuiGitStatus:mount()
  return self._layout:mount()
end


function NuiGitStatus:write_index()
  if self._updated then
    if self.index:write() == 0 then
      self._updated = false
    end
  end
end


-- Makes a commit
---@param message string
function NuiGitStatus:commit(message)
  if message == "" then
    vim.notify("Empty commit message", vim.log.levels.ERROR)
    return
  end

  local sign, prettified, err

  prettified, err = git2.message_prettify(message)
  if err ~= 0 then
    vim.notify("Failed to clean message", vim.log.levels.ERROR)
    return
  end

  self:write_index()

  sign, err = self.repo:signature_default()
  if err ~= 0 then
    vim.notify("Failed to get default author, code: " .. err, vim.log.levels.ERROR)
    return
  end

  if sign and prettified then
    err = self.repo:commit(self.index, sign, prettified)
    if err == 0 then
      self:update()
    else
      vim.notify("Failed to create commit, code: " .. err, vim.log.levels.ERROR)
    end
  end
end


-- Setup keymap handlers
function NuiGitStatus:setup_handlers()
  local map_options = { noremap = true }
  local tree = self._tree

  local exit_fn = function()
    self:write_index()
    self._layout:unmount()
  end

  -- exit
  self.file_popup:map("n", "q", exit_fn, map_options)
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

  -- make commit
  self.file_popup:map("n", "c",
    function ()
      self._layout:update(self._input_box)
      vim.api.nvim_set_current_win(self.input_popup.winid)
      vim.cmd("startinsert")
    end,
    map_options
  )
end


return NuiGitStatus
