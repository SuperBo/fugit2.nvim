-- Fugit2 Git diff view tab module

local LogLevel = vim.log.levels

local event = require("nui.utils.autocmd").event
local NuiLayout = require "nui.layout"
local NuiSplit = require "nui.split"
local Object = require "nui.object"
local Path = require "plenary.path"

local SourceTree = require "fugit2.view.components.source_tree_view"
local git2 = require "fugit2.git2"

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
---@field ns_id integer
---@field tabpage integer
local GitDiff = Object "Fugit2GitDiffView"

---Initializes GitDiffView
---@param ns_id integer Namespace id
---@param repo GitRepository git repository
---@param index GitIndex?
function GitDiff:init(ns_id, repo, index)
  self.ns_id = ns_id
  self.repo = repo

  if index then
    self.index = index
  else
    local _index, err = repo:index()
    if not _index then
      error("[Fugit2] Can't create index from repo " .. err, LogLevel.ERROR)
    end
    self.index = _index
  end

  -- sub views
  self._views = {}
  self._windows = {}

  -- git info
  self._git = {
    path = vim.fn.fnamemodify(repo:repo_path(), ":p:h:h"),
  }

  -- states
  self._states = {
    pane = Pane.SINGLE,
    -- file buffer cache
    buffers = {},
    last_line = -1,
  }
end

-- Open GitDiffView in new tab
function GitDiff:mount()
  if self.tabpage and vim.api.nvim_tabpage_is_valid(self.tabpage) then
    vim.api.nvim_set_current_tabpage(self.tabpage)
  else
    vim.cmd.tabnew()
    self.tabpage = vim.api.nvim_tabpage_get_number(0)
    self:_post_mount()
  end
end

---Update info based on index
function GitDiff:update()
  -- Clears status

  -- Updates
  local status_files, err = self.repo:status()
  if status_files then
  end
end

function GitDiff:render()
  self._views.files:render()
end

function GitDiff:_post_mount()
  self._windows[1] = vim.api.nvim_get_current_win()

  local source_tree = SourceTree(self.ns_id)
  self._views.files = source_tree

  self:_setup_handlers()
  source_tree:mount()

  vim.cmd "rightbelow vsplit"
  self._windows[2] = vim.api.nvim_get_current_win()

  self._states.pane = Pane.TWO

  source_tree:focus()
  self:update()
  self:render()
end

---Switches to two main panes layout

-- Unmount Diffview remove buffers
function GitDiff:umount()
end


-- Update info based on index
function GitDiff:update()
  -- Clears status

  -- Updates git source tree status
  local status_files, err = self.repo:status()
  if status_files then
    self._views.files:update(status_files)
  else
    vim.notify("[Fugit2] Error updating git status, err " .. err)
  end
end


function GitDiff:render()
  self._views.files:render()
end


-- Writes an index file to git index.
---@param bufnr integer buffer number
function GitDiff:_write_index(bufnr, filepath)
  -- add to index
  local entry = self.index:get_bypath(filepath, git2.GIT_INDEX_STAGE.NORMAL)
  if not entry then
    vim.ui.notify("[Fugit2] Failed to get index entry")
    return
  end

  local content_buffer = table.concat(
    vim.api.nvim_buf_get_lines(bufnr, 0, -1, true), "\n"
  )
  -- add newline at the end
  content_buffer = content_buffer .. "\n"

  local err = self.index:add_from_buffer(entry, content_buffer)
  if err ~= 0 then
    vim.ui.notify(
      string.format("[Fugit2] Failed to write to buffer, code: %d", err),
      vim.logs.levels.ERROR
    )
    return
  end

  -- reset modified option
  vim.api.nvim_buf_set_option(bufnr, "modifed", false)
end


-- Switches to two main panes layout
function GitDiff:_two_panes_layout() end

-- Switches to three main panes layout
function GitDiff:_three_panes_layout() end


-- Setups diff files in windows
---@param node NuiTree.Node
function GitDiff:_setup_diff_windows(node)
  local windows = self._windows
  local git = self._git
  local buffer = self._states.buffers
  local node_id = node:get_id()
  local filetype = vim.filetype.match { filename = node.text }

  if node.status == SourceTree.GIT_STATUS.UNSTAGED then
    -- Unstaged file
    local file_path = Path:new(git.path) / node.text
    file_path = vim.fn.fnameescape(file_path:make_relative())

    -- Workdir file
    vim.schedule(function()
      vim.fn.win_execute(windows[2], "edit " .. file_path)
    end)

    -- Index file
    local bufnr = buffer[node_id]
    if bufnr then
      vim.api.nvim_win_set_buf(windows[1], bufnr)
    else
      bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr, "index::" .. node.text)
      buffer[node_id] = bufnr
      vim.api.nvim_win_set_buf(windows[1], bufnr)

      -- read raw content
      local entry = self.index:get_bypath(node.text, git2.GIT_INDEX_STAGE.NORMAL)
      if entry then
        local blob, err = self.repo:blob_lookup(entry:id())
        if not blob then
          vim.ui.notify("[Fugit2] Can't get blob, error " .. err, vim.logs.levels.ERROR)
        else
          local content = vim.split(blob:content(), "\n", { plain=true })
          if content[#content] == "" then
            content[#content] = nil
          end
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
        end
      end

      vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
      if filetype then
        vim.api.nvim_buf_set_option(bufnr, "filetype", filetype)
      end
    end

    -- setup vim diff
    vim.schedule(function()
      vim.cmd "diffoff!"
      vim.fn.win_execute(windows[2], "diffthis")
      vim.fn.win_execute(windows[1], "diffthis")
    end)
  end
end


function GitDiff:_setup_handlers()
  local opts = { noremap = true, nowait = true }
  local windows = self._windows
  local source_tree = self._views.files

  source_tree:map("n", { "q", "<esc>" }, ":tabclose<cr>", opts)

  source_tree:map("n", "l", "<c-w>l", opts)

  -- SourceTree event
  source_tree:on(event.CursorMoved, function()
    local node, linenr = source_tree:get_node()

    if not node
      or linenr == self._states.last_line
      or not vim.api.nvim_win_is_valid(windows[2])
    then
      return
    end

    self._states.last_line = linenr

    self:_setup_diff_windows(node)
  end)
end

return GitDiff
