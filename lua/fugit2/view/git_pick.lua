-- Fugit2 Git picker module

local NuiInput = require "nui.input"
local NuiLayout = require "nui.layout"
local NuiText = require "nui.text"

local GitGraph = require "fugit2.view.git_graph"
local fzf = require "fugit2.core.fzf"

local ENTITY = GitGraph.ENTITY
local BRANCH_WINDOW_WIDTH = 36

-- Pre-allocated memory slices to minimize GC
local SLAB16_SIZE = 1024 -- 2B * 1K = 2KB
local SLAB32_SIZE = 256 -- 4B * 256 = 1KB

fzf.init "default"

---@class Fugit2GitPickView: Fugit2GitGraphView
local GitPick = GitGraph:extend "Fugit2GitPickView"

-- Inits Fugit2GitPick
---@param ns_id integer
---@param repo GitRepository
---@param type Fugit2GitGraphEntity
---@param title string title for search bar
function GitPick:init(ns_id, repo, type, title)
  self._views = {
    input = NuiInput({
      ns_id = ns_id,
      border = {
        style = "rounded",
        padding = { top = 0, bottom = 0, left = 1, right = 1 },
        text = {
          top = NuiText(title, "Fugit2FloatTitle"),
          top_align = "left",
        },
      },
      enter = true,
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
    }, {
      prompt = NuiText("> ", "Fugit2BranchHead"),
      default_value = "",
      on_submit = function(value)
        if self._states.callback then
          self._states.callback(self._states.last_ref)
        end
      end,
      on_change = function(value)
        self:on_input_change(type, value)
      end,
    }),
  }

  GitGraph.init(self, ns_id, repo)

  self._states.entity = type
  self._states.slab = fzf.new_slab(SLAB16_SIZE, SLAB32_SIZE)
  self._states.last_value = ""

  self._views.log.popup._.win_enter = false

  self._layout:update(NuiLayout.Box({
    NuiLayout.Box(self._views.input, { size = 3 }),
    NuiLayout.Box({
      NuiLayout.Box(self._views.branch.popup, { size = BRANCH_WINDOW_WIDTH }),
      NuiLayout.Box(self._views.log.popup, { grow = 1 }),
    }, { dir = "row", grow = 1 }),
  }, { dir = "col" }))
end

-- Handles when tags_branches input changes
---@param type Fugit2GitGraphEntity
---@param value string
function GitPick:on_input_change(type, value)
  local states = self._states

  if value == states.last_value then
    return
  end

  states.last_value = value

  -- fuzzy matching
  local slab = states.slab

  if value ~= "" then
    local matches = {}

    if type == ENTITY.TAG then
      for _, tag in ipairs(states.contents) do
        local match, pos = fzf.fuzzy_match_v2(false, false, true, tag, value, true, slab)
        if match.start and match.stop then
          matches[#matches + 1] = { text = tag, score = match.score, pos = pos }
        end
      end

      table.sort(matches, function(a, b)
        return a.score > b.score
      end)
      self._views.branch:update_tags_match(matches)
    else
      for _, br in ipairs(states.contents) do
        local match, pos = fzf.fuzzy_match_v2(false, false, true, br.shorthand, value, true, slab)
        if match.start and match.stop then
          matches[#matches + 1] = { branch = br, score = match.score, pos = pos }
        end
      end

      table.sort(matches, function(a, b)
        return a.score > b.score
      end)
      self._views.branch:update_branches_match(matches)
    end
  elseif type == ENTITY.TAG then
    self._views.branch:update_tags(states.contents)
  else
    self._views.branch:update_branches(states.contents, states.active)
  end

  -- update content
  vim.schedule(function()
    local pos = self._views.branch:get_cursor()
    self._views.branch:render()
    self._views.branch:set_cursor(pos[1], pos[2])

    local node, _ = self._views.branch:get_child_node_linenr()
    if not node then
      states.last_ref = ""
      self:clear_log()
      self._views.log:render()
    elseif node.id ~= states.last_ref then
      states.last_ref = node.id
      self:update_log(node.id)
      self._views.log:render()
    end
  end)
end

-- Override mount with setting correct last_ref
---@overide
function GitPick:mount()
  self._layout:mount()
  self._views.branch:scroll_to_active_branch()

  local node, linenr = self._views.branch:get_child_node_linenr()
  if node and linenr then
    self._states.last_ref = node.id
    self._states.last_branch_linenr = linenr
  end
end

---@param callback function
function GitPick:on_submit(callback)
  self._states.callback = callback
end

-- Setup handlers
function GitPick:setup_handlers()
  local opts = { nowait = true, noremap = true }
  local states = self._states
  local input = self._views.input
  local branch_view = self._views.branch

  input:map("i", "<C-n>", function()
    local pos = branch_view:get_cursor()
    branch_view:set_cursor(pos[1] + 1, pos[2])

    local node, linenr = branch_view:get_child_node_linenr()
    if node and linenr and linenr ~= states.last_branch_linenr then
      states.last_branch_linenr = linenr
      states.last_ref = node.id
      self:update_log(node.id)
      self._views.log:render()
    end
  end, opts)

  input:map("i", "<C-p>", function()
    local pos = branch_view:get_cursor()
    branch_view:set_cursor(pos[1] - 1, pos[2])

    local node, linenr = branch_view:get_child_node_linenr()
    if node and linenr and linenr ~= states.last_branch_linenr then
      states.last_branch_linenr = linenr
      states.last_ref = node.id
      self:update_log(node.id)
      self._views.log:render()
    end
  end, opts)

  input:map("i", { "<esc>", "<C-c>" }, function()
    self:unmount()
  end, opts)
end

GitPick.ENTITY = ENTITY

return GitPick
