-- Fugit2 Diff view pannel with git support

local NuiPopup = require "nui.popup"
local Object = require "nui.object"
local event = require("nui.utils.autocmd").event

---@class Fugit2DiffView Diff view panel, used in git status
---@field ns_id integer namespace id
---@field title string initial tile
---@field popup NuiPopup
local DiffView = Object "Fugit2DiffView"

---@param ns_id integer
---@param title string
---@param bufnr integer?
function DiffView:init(ns_id, title, bufnr)
  self.ns_id = ns_id
  self.title = title

  local opts = {
    ns_id = ns_id,
    position = "50%",
    size = {
      width = 80,
      height = 40,
    },
    enter = true,
    focusable = true,
    border = {
      padding = {
        left = 1,
        right = 1,
      },
      style = "rounded",
      text = { top = { title } },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      number = true,
      -- diffopt = "internal,filler,context:3,foldcolumn:2,linematch:60"
      -- diffopt = "internal,filler,context:3,foldcolumn:2,linematch:60"
    },
  }
  if bufnr then
    opts.bufnr = bufnr
  end

  -- popup
  self.popup = NuiPopup(opts)

  self.popup:on(event.BufEnter, function()
    -- to avoid conflict with vim-ufo
    if vim.fn.exists ":UfoDetach" > 0 then
      vim.cmd "UfoDetach"
    end
  end, { once = true })
end

function DiffView:mount()
  return self.popup:mount()
end

function DiffView:unmount()
  return self.popup:unmount()
end

function DiffView:winid()
  return self.popup.winid
end

function DiffView:bufnr()
  return self.popup.bufnr
end

---@param mode string
---@param key string|string[]
---@param fn fun()|string
---@param opts table
function DiffView:map(mode, key, fn, opts)
  return self.popup:map(mode, key, fn, opts)
end

---@param bufnr integer
function DiffView:set_bufnr(bufnr)
  self.popup.bufnr = bufnr
end

return DiffView
