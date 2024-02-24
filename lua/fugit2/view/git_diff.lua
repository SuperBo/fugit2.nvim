-- Fugit2 Git diff view tab module

local LogLevel = vim.log.levels

local NuiLayout = require "nui.layout"
local NuiSplit = require "nui.split"
local Object = require "nui.object"

local SourceTree = require "fugit2.view.components.source_tree_view"

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
---@param repo GitRepository
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
  self._pane = Pane.SINGLE
end

---Creates new tab
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
  source_tree:mount()

  vim.cmd "rightbelow vsplit"
  self._windows[2] = vim.api.nvim_get_current_win()

  self._pane = Pane.TWO

  source_tree:focus()
  self:update()
  self:render()
end

---Switches to two main panes layout
function GitDiff:_two_panes_layout() end

---Switches to three main panes layout
function GitDiff:_three_panes_layout() end

return GitDiff
