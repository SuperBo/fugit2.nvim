-- Fugit2 Patch view pannel with git support

local NuiPopup = require "nui.popup"
local Object = require "nui.object"
local event = require "nui.utils.autocmd".event


---@class Fugit2PatchView
---@field ns_id integer namespace id
---@field title string initial tile
---@field popup NuiPopup
local PatchView = Object("Fugit2PatchView")


---@param ns_id integer
---@param title string
function PatchView:init(ns_id, title)
  self.ns_id = ns_id
  self.title = title

  -- popup
  self.popup = NuiPopup {
    ns_id = ns_id,
    position = "50%",
    size = {
      width = 80,
      height = 40,
    },
    enter = false,
    focusable = true,
    border = {
      padding = {
        left = 1,
        right = 1,
      },
      style = "rounded",
      text = { top = {} }
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      filetype = "diff",
      buftype = "nofile",
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = true,
    },
  }

  -- sub components
  self._header = {}
  self._hunks = {}

  self.popup:on(event.BufEnter, function()
    -- to avoid conflict with vim-ufo
    if vim.fn.exists(':UfoDetach') > 0 then
      vim.cmd("UfoDetach")
    end
    vim.api.nvim_win_set_option(self.popup.winid, "foldmethod", "expr")
    vim.api.nvim_win_set_option(self.popup.winid, "foldexpr", "Fugit2DiffFold(v:lnum)")
  end, { once = true })

  -- keymaps
  local opts = { noremap = true, nowait = true }
  -- self.popup:map("n", "=", "za", opts)
  self.popup:map("n", "J", self:next_hunk_handler(), opts)
  self.popup:map("n", "K", self:prev_hunk_handler(), opts)
  -- local expand_collapse_handler = self:expand_collapse_handler()
  -- self.popup:map("n", "<cr>", expand_collapse_handler, opts)
  -- self.popup:map("n", "l", self:expand_handler(), opts)
  -- self.popup:map("n", "H", self:collapse_all_handler(), opts)
  -- self.popup:map("n", "L", self:expand_all_handler(), opts)
end

---Updates content with a given patch
---@param patch_item GitDiffPatchItem
function PatchView:update(patch_item)
  local patch = patch_item.patch
  local stats
  local header, hunks = {}, { 1 }

  stats, _ = patch:stats()
  if stats then
    self.popup.border:set_text(
      "top",
      self.title .. " +" .. stats.insertions .. " -" .. stats.deletions,
      "left"
    )
  end

  local lines = vim.split(tostring(patch), "\n", { plain=true, trimempty=true })

  for i, l in ipairs(lines) do
    if l:sub(1, 1) ~= "@" then
      header[i] = l
    else
      break
    end
  end

  local render_lines = vim.list_slice(lines, #header + 1)

  local line_num = hunks[1]
  local num_hunks = tonumber(patch:nhunks())
  for i = 0,num_hunks-1 do
    line_num = line_num + patch:hunk_num_lines(i) + 1
    hunks[i+2] = line_num
  end

  self._header, self._hunks = header, hunks
  self:render(render_lines)
end

---@param lines string[]
function PatchView:render(lines)
  vim.api.nvim_buf_set_option(self.popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(self.popup.bufnr, "readonly", false)

  vim.api.nvim_buf_set_lines(
    self.popup.bufnr, 0, -1, true, lines
  )

  vim.api.nvim_buf_set_option(self.popup.bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(self.popup.bufnr, "readonly", true)
end

function PatchView:mount()
  return self.popup:mount()
end

function PatchView:unmount()
  return self.popup:unmount()
end

function PatchView:focus()
  vim.api.nvim_set_current_win(self.popup.winid)
end

---@param mode string
---@param key string|string[]
---@param fn fun()|string
---@param opts table
function PatchView:map(mode, key, fn, opts)
  return self.popup:map(mode, key, fn, opts)
end

---Gets current hunk based current cursor position
---@return integer hunk_index
---@return integer hunk_offset
---@return integer cursor_row
---@return integer cursor_col
function PatchView:get_current_hunk()
  local cursor = vim.api.nvim_win_get_cursor(self.popup.winid)

  if cursor[1] < self._hunks[1] then
    return 0, 1, cursor[1], cursor[2]
  end

  if #self._hunks > 8 then
    -- do binary search
    local start, stop  = 1, #self._hunks
    local mid, hunk_offset

    while start < stop-1 do
      mid = math.floor((start + stop) / 2)
      hunk_offset = self._hunks[mid]
      if cursor[1] == hunk_offset then
        return mid, hunk_offset, cursor[1], cursor[2]
      elseif cursor[1] < hunk_offset then
        stop = mid
      else
        start = mid
      end
    end
    return start, self._hunks[start], cursor[1], cursor[2]
  else
    -- do linear search
    for i, hunk_offset in ipairs(self._hunks) do
      if cursor[1] < hunk_offset then
        return i-1, self._hunks[i-1] or 1, cursor[1], cursor[2]
      elseif cursor[1] == hunk_offset then
        return i, hunk_offset, cursor[1], cursor[2]
      end
    end
  end

  return 0, 1, cursor[1], cursor[2]
end

---@return fun()
function PatchView:next_hunk_handler()
  return function()
    local hunk_idx, _, _, col = self:get_current_hunk()
    local new_row = self._hunks[hunk_idx+1]
    if hunk_idx + 1 == #self._hunks then
      new_row = new_row - 1
    end
    vim.api.nvim_win_set_cursor(self.popup.winid, { new_row, col })
  end
end

---@return fun()
function PatchView:prev_hunk_handler()
  return function()
    local hunk_idx, hunk_offset, row, col = self:get_current_hunk()
    local new_row = hunk_offset
    if hunk_offset == row then
      if hunk_idx <= 1 then
        new_row = 1
      else
        new_row = self._hunks[hunk_idx-1]
      end
    end
    vim.api.nvim_win_set_cursor(self.popup.winid, { new_row, col })
  end
end

---@return string?
function PatchView:get_partial_diff_hunk()
  local hunk_idx, _, _, _ = self:get_current_hunk()
  if hunk_idx > 0 then
    local hunk = vim.api.nvim_buf_get_lines(
      self.popup.bufnr, self._hunks[hunk_idx] - 1, self._hunks[hunk_idx+1] - 1, true
    )
    local diff_lines = vim.list_extend(vim.list_slice(self._header), hunk)
    return table.concat(diff_lines, "\n") .. "\n"
  end
end


return PatchView
