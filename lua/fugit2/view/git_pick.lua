-- Fugit2 Git picker module

local NuiInput = require "nui.input"
local NuiLayout = require "nui.layout"
local NuiText = require "nui.text"
local iter = require "plenary.iterators"

local GitGraph = require "fugit2.view.git_graph"
local utils = require "fugit2.utils"


local BRANCH_WINDOW_WIDTH = 36
local GIT_OID_LENGTH = 16


---@class Fugit2GitPickView: Fugit2GitGraphView
local GitPick = GitGraph:extend "Fugit2GitPickView"

-- Inits Fugit2GitPick
---@param ns_id integer
---@param repo GitRepository
---@param type Fugit2GitGraphEntity
function GitPick:init(ns_id, repo, type)
  GitGraph.init(self, ns_id, repo)

  self._states.entity = type

  self._views["input"] = NuiInput(
    {
      ns_id = ns_id,
      border = {
        style = "rounded",
        padding = { top = 0, bottom = 0, left = 1, right = 1 },
        -- text = {
        --   top = "[Input]",
        --   top_align = "left",
        -- },
      },
      enter = true,
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
    },
    {
      prompt = NuiText("> ", "Fugit2BranchHead"),
      default_value = "42",
      on_close = function()
        print("Input closed!")
      end,
      on_submit = function(value)
        print("Value submitted: ", value)
      end,
      on_change = function(value)
        print("Value changed: ", value)
      end,
    }
  )
  self._views["log"].popup._.win_enter = false

  self._layout:update(
    NuiLayout.Box({
      NuiLayout.Box(self._views.input, { size = 3 }),
      NuiLayout.Box({
        NuiLayout.Box(self._views.branch.popup, { size = BRANCH_WINDOW_WIDTH }),
        NuiLayout.Box(self._views.log.popup, { grow = 1 }),
      }, { dir = "row", grow = 1 }),
    }, { dir = "col" })
  )
end


-- Setup handlers
function GitPick:setup_handlers()
end


return GitPick
