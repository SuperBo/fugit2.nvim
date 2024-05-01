-- Fugit2 Git diff view tab module

local LogLevel = vim.log.levels
local uv = vim.loop

local NuiLine = require "nui.line"
local NuiText = require "nui.text"
local Object = require "nui.object"
local Path = require "plenary.path"
local event = require("nui.utils.autocmd").event

local git2 = require "fugit2.git2"
local SourceTree = require "fugit2.view.components.source_tree_view"
local UI = require "fugit2.view.components.menus"


local GIT_OID_LENGTH = 8

---@enum Fugit2GitDiffViewPane
local Pane = {
  INVALID = 0, -- Pane have been invalid
  SINGLE = 1, -- Pane in single mode, usually at start
  TWO = 2, -- Pane in two side mode
  THREE = 3, -- Pane in three way compare
}

---@class Fugit2GitDiffView
---@field repo GitRepository
---@field index GitIndex
---@field head GitCommit?
---@field ns_id integer
---@field tabpage integer
local GitDiff = Object "Fugit2GitDiffView"

---Initializes GitDiffView
---@param ns_id integer Namespace id
---@param repo GitRepository git repository
---@param index GitIndex?
---@param head_commit GitCommit?
function GitDiff:init(ns_id, repo, index, head_commit)
  self.ns_id = ns_id
  self.repo = repo

  if index then
    self.index = index
  else
    local _index, err = repo:index()
    if not _index then
      error("[Fugit2] Can't create index from repo " .. err)
    end
    self.index = _index
  end

  local _head_commit = head_commit
  if not head_commit then
    local _commit, err = repo:head_commit()
    if not _commit and err ~= git2.GIT_ERROR.GIT_EUNBORNBRANCH then
      error("[Fugit2] Can't retrieve repo head " .. err)
    end
    _head_commit = _commit
  end

  -- sub views
  self._views = {}
  self._windows = {}

  -- git info
  self._git = {
    path = vim.fn.fnamemodify(repo:repo_path(), ":p:h:h"),
    head_name = "head::",
    head_tree = nil,
  }

  if _head_commit then
    self._git.head_name = _head_commit:id():tostring(GIT_OID_LENGTH) .. "::"

    local _tree, err = _head_commit:tree()
    if _tree then
      self._git.head_tree = _tree
    else
      error("[Fugit2] Cant' retrieve head tree" .. err)
    end
  end

  -- states
  self._states = {
    pane = Pane.SINGLE,
    -- file buffer cache
    buffers = {},
    last_line = -1,
    index_updated = false,
    init_buffer = -1,
    active_node = nil,
  }
end

-- Open GitDiffView in new tab
function GitDiff:mount()
  if self.tabpage and vim.api.nvim_tabpage_is_valid(self.tabpage) then
    vim.api.nvim_set_current_tabpage(self.tabpage)
  else
    vim.cmd.tabnew()
    self._states.init_buffer = vim.api.nvim_get_current_buf()
    self.tabpage = vim.api.nvim_tabpage_get_number(0)
    self:_post_mount()
  end
end

function GitDiff:render()
  self._views.files:render()
end

function GitDiff:_post_mount()
  self._windows[1] = vim.api.nvim_get_current_win()

  local source_tree = SourceTree(self.ns_id)
  self._views.files = source_tree

  source_tree:mount()
  source_tree:set_buf_name("Source Tree")

  vim.cmd "rightbelow vsplit"
  self._windows[2] = vim.api.nvim_get_current_win()

  self._states.pane = Pane.TWO

  self:_setup_handlers()

  source_tree:focus()
  self:update()
  self:render()
end


-- Unmount Diffview remove buffers
function GitDiff:unmount()
  local save_queue = {}
  local files = {}

  -- check unsaved buffers
  for _, bufnr in pairs(self._states.buffers) do
    local name = ""
    if vim.api.nvim_buf_is_loaded(bufnr) then
      name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
    end

    if name:sub(1, 7) == "index::"
      and vim.api.nvim_buf_get_option(bufnr, "modified")
    then
      save_queue[#save_queue+1] = bufnr
      files[#files+1] = name
    end
  end

  if #save_queue == 0 then
    self:_destroy()
    return
  end

  local confirm = UI.Confirm(
    self.ns_id,
    NuiLine {
      NuiText(string.format("Do you want to save %s to index?", files[#files]:sub(8)))
    }
  )
  confirm:on_yes(
    function()
      self:_write_index(files[#files], save_queue[#save_queue])
    end
  )
  confirm:on_exit(function()
    -- pop last of queue
    save_queue[#save_queue] = nil
    files[#files] = nil

    if #save_queue == 0 or #files == 0 then
      vim.schedule(function() self:_destroy() end)
      return
    end

    confirm:set_text(NuiLine {
      NuiText(string.format("Do you want to save %s to index?", files[#files]:sub(8)))
    })

    vim.schedule(function() confirm:show() end)
  end)

  confirm:mount()
end


-- Destroys GitDiff tab
function GitDiff:_destroy()
  -- close windows
  vim.api.nvim_win_close(self._windows[1], true)
  vim.api.nvim_win_close(self._windows[2], true)
  if self._states.pane == Pane.THREE then
    vim.api.nvim_win_close(self._windows[3], true)
  end

  -- close buffers
  for _, bufnr in pairs(self._states.buffers) do
    local name = ""
    if vim.api.nvim_buf_is_loaded(bufnr) then
      name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
    end

    if name:sub(1, 7) == "index::"
      or name:sub(1, 6) == "head::"
      or name:sub(GIT_OID_LENGTH+1, GIT_OID_LENGTH+2) == "::"
    then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  -- write index back to disk
  if self._states.index_updated and not self.index:in_memory() then
    self.index:write()
    self._states.index_updated = false
  end

  if vim.api.nvim_buf_is_valid(self._states.init_buffer) then
    vim.api.nvim_buf_delete(self._states.init_buffer, { force = true })
  end

  self._views.files:unmount()
end


-- Update info based on index
function GitDiff:update()
  -- Clears status

  -- Updates git source tree status
  local status_files, err = self.repo:status()
  if status_files then
    self._views.files:update(status_files)
  else
    vim.notify("[Fugit2] Error updating git status, err " .. err, LogLevel.ERROR)
  end
end


-- Set tree nodes modified
---@param bufnr integer buffer nnumber
---@param filepath string git filepath
function GitDiff:_set_modified_path(bufnr, filepath)
  local is_modified = vim.api.nvim_buf_get_option(bufnr, "modified")

  local node = self._views.files:get_node("-staged-" .. filepath)
  if node then
    node.modified = is_modified
  end

  node = self._views.files:get_node("-unstaged-" .. filepath)
  if node then
    node.modified = is_modified
  end

  self._views.files:render()
end


-- Writes an index file to git index.
---@param filepath string
---@param bufnr integer
---@return boolean success whether write success
function GitDiff:_write_index(filepath, bufnr)
  if filepath:sub(1, 7) ~= "index::" then
    vim.notify("[Fugit2] Wrong index file name", LogLevel.ERROR)
    return false
  end
  filepath = filepath:sub(8)

  -- add to index
  local entry = self.index:get_bypath(filepath, git2.GIT_INDEX_STAGE.NORMAL)
  if not entry then
    local stat = uv.fs_stat(filepath)
    if stat then
      entry = git2.IndexEntry.from_stat(stat, filepath, true)
    else
      vim.notify("[Fugit2] Failed to create new index entry", LogLevel.ERROR)
      return false
    end
  end

  local content_buffer = table.concat(
    vim.api.nvim_buf_get_lines(bufnr, 0, -1, true), "\n"
  )
  -- add newline at the end
  content_buffer = content_buffer .. "\n"

  local err = self.index:add_from_buffer(entry, content_buffer)
  if err ~= 0 then
    vim.notify(
      "[Fugit2] Failed to write to buffer, code: " .. err,
      LogLevel.ERROR
    )
    return false
  end

  -- reset modified option
  vim.api.nvim_buf_set_option(bufnr, "modified", false)

  vim.notify(string.format("[Fugit2] Saved %s to index", filepath), LogLevel.INFO)
  self._states.index_updated = true
  return true
end


-- Switches to two main panes layout
function GitDiff:_two_panes_layout() end

-- Switches to three main panes layout
function GitDiff:_three_panes_layout() end


-- Creates a buffer coressponding to a index file.
-- Return a cached result if buffer is created before.
---@param path string git file path
---@param filetype string? file type
---@return integer buffer buffer number
function GitDiff:_get_or_create_index_buffer(path, filetype)
  local buf_key = "index::" .. path
  local bufnr = self._states.buffers[buf_key]
  if bufnr then
    return bufnr
  end

  bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, buf_key)
  self._states.buffers[buf_key] = bufnr

  -- read raw content
  local entry = self.index:get_bypath(path, git2.GIT_INDEX_STAGE.NORMAL)
  if entry then
    local blob, err = self.repo:blob_lookup(entry:id())
    if not blob then
      vim.notify(
        string.format("[Fugit2] Can't get blob, error %d", err), LogLevel.ERROR
      )
    else
      local content = vim.split(blob:content(), "\n", { plain=true })
      if content[#content] == "" then
        content[#content] = nil
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
    end
  end

  vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
  vim.api.nvim_create_autocmd({event.BufWriteCmd}, {
    buffer = bufnr,
    callback = function(e)
      if self:_write_index(e.file, e.buf) then
        self:update()
        self:render()
      end
    end
  })
  if filetype then
    vim.api.nvim_buf_set_option(bufnr, "filetype", filetype)
  end
  vim.api.nvim_buf_set_option(bufnr, "modified", false)

  -- setup buffer event
  vim.api.nvim_create_autocmd({event.BufModifiedSet}, {
    buffer = bufnr,
    callback = function(e) self:_set_modified_path(bufnr, path) end
  })

  return bufnr
end


-- Creates a buffer coressponding to a head file.
-- Returns a cached result if buffer is created before.
---@param path string git file path
---@param filetype string? file type
---@return integer buffer buffer number
function GitDiff:_get_or_create_head_buffer(path, filetype)
  local buf_key = "head::" .. path
  local bufnr = self._states.buffers[buf_key]
  if bufnr then
    return bufnr
  end

  bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, self._git.head_name .. path)
  self._states.buffers[buf_key] = bufnr

  -- read from git commit
  local head_tree = self._git.head_tree
  if head_tree then
    local entry, obj, err
    entry, err = head_tree:entry_bypath(path)
    if not entry then
      vim.notify("[Fugit2] Failed to get tree entry!".. err, LogLevel.ERROR)
    else
      obj, err = entry:to_object(self.repo)
      if not obj then
        vim.notify("[Fugit2] Failed to get git object!" .. err, LogLevel.ERROR)
      else
        local content = vim.split(obj:as_blob():content(), "\n", { plain = true })
        if content[#content] == "" then
          content[#content] = nil
        end
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
      end
    end
  end

  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  if filetype then
    vim.api.nvim_buf_set_option(bufnr, "filetype", filetype)
  end
  return bufnr
end


-- Setups diff files in windows
---@param node NuiTree.Node
function GitDiff:_setup_diff_windows(node)
  local windows = self._windows
  local git = self._git
  local filetype = vim.filetype.match { filename = node.text }

  if node.status == SourceTree.GIT_STATUS.UNSTAGED then
    -- Unstaged file
    local file_path = Path:new(git.path) / node.text
    file_path = vim.fn.fnameescape(file_path:make_relative())

    -- Index file
    local bufnr = self:_get_or_create_index_buffer(node.text, filetype)

    -- setup vim diff
    vim.schedule(function()
      vim.cmd.diffoff { bang = true }
      vim.fn.win_execute(windows[2], "edit " .. file_path)
      vim.api.nvim_win_set_buf(windows[1], bufnr)
      vim.fn.win_execute(windows[2], "diffthis")
      vim.fn.win_execute(windows[1], "diffthis")
    end)
  elseif node.status == SourceTree.GIT_STATUS.STAGED then
    -- Index file
    local bufnr2 = self:_get_or_create_index_buffer(node.text, filetype)

    -- Head file
    local bufnr1 = self:_get_or_create_head_buffer(node.text, filetype)

    vim.schedule(function()
      vim.cmd.diffoff { bang = true }
      vim.api.nvim_win_set_buf(windows[2], bufnr2)
      vim.api.nvim_win_set_buf(windows[1], bufnr1)
      vim.fn.win_execute(windows[2], "diffthis")
      vim.fn.win_execute(windows[1], "diffthis")
    end)
  end
end


function GitDiff:_setup_handlers()
  local opts = { noremap = true, nowait = true }
  local windows = self._windows
  local source_tree = self._views.files

  source_tree:map("n", { "q", "<esc>" }, function()
    self:unmount()
  end, opts)

  source_tree:map("n", { "l", "<cr>" }, "<c-w>l", opts)

  -- SourceTree handlers
  -- source_tree:on(event.BufWinLeave, function()
  --   self:unmount()
  -- end, opts)

  source_tree:on(event.CursorMoved, function()
    local node, linenr = source_tree:get_node()

    if not node
      or linenr == self._states.last_line
      or not vim.api.nvim_win_is_valid(windows[2])
    then
      return
    end

    self._states.last_line = linenr
    self._states.active_node = node
    self:_setup_diff_windows(node)
  end)
end

return GitDiff
