-- Fugit2 Patch view pannel with git support

local NuiText = require "nui.text"
local NuiPopup = require "nui.popup"
local Object = require "nui.object"
local event = require "nui.utils.autocmd".event

local diff_utils = require "fugit2.diff"


---@class Fugit2PatchView
---@field ns_id integer namespace id
---@field title string initial tile
---@field popup NuiPopup
local PatchView = Object("Fugit2PatchView")


---@param ns_id integer
---@param title string
---@param title_color string
function PatchView:init(ns_id, title, title_color)
  self.ns_id = ns_id
  self.title = title
  self.title_color = title_color

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
  ---@type string[]
  self._header = {}
  ---@type integer[]
  self._hunk_offsets = {}
  ---@type GitDiffHunk[]
  self._hunk_diffs = {}

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

function PatchView:winid()
  return self.popup.winid
end

---Updates content with a given patch
---@param patch_item GitDiffPatchItem
function PatchView:update(patch_item)
  local patch = patch_item.patch
  local stats
  local header, hunk_offsets, hunk_diffs = {}, { 1 }, {}

  stats, _ = patch:stats()
  if stats then
    self.popup.border:set_text(
      "top",
      NuiText(
        string.format(" %s +%d -%d ", self.title, stats.insertions, stats.deletions ),
        self.title_color
      ),
      "center"
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

  local line_num = hunk_offsets[1]
  for i = 0,patch_item.num_hunks-1 do
    local diff_hunk, _ = patch:hunk(i)
    if diff_hunk then
      hunk_diffs[i+1] = diff_hunk
      line_num = line_num + diff_hunk.num_lines + 1
    end
    hunk_offsets[i+2] = line_num
  end

  self._header = header
  self._hunk_offsets = hunk_offsets
  self._hunk_diffs = hunk_diffs

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


---@param offsets integer[]
---@param cursor_row integer
---@return integer hunk_index
---@return integer hunk_offset
local function get_hunk(offsets, cursor_row)
  if cursor_row < offsets[1] then
    return 0, 1
  end

  if #offsets > 6 then
    -- do binary search
    local start, stop  = 1, #offsets
    local mid, hunk_offset

    while start < stop-1 do
      mid = math.floor((start + stop) / 2)
      hunk_offset = offsets[mid]
      if cursor_row == hunk_offset then
        return mid, hunk_offset
      elseif cursor_row < hunk_offset then
        stop = mid
      else
        start = mid
      end
    end
    return start, offsets[start]
  else
    -- do linear search
    for i, hunk_offset in ipairs(offsets) do
      if cursor_row < hunk_offset then
        return i-1, offsets[i-1] or 1
      elseif cursor_row == hunk_offset then
        return i, hunk_offset
      end
    end
  end

  return 0, 1
end


---Gets current hunk based current cursor position
---@return integer hunk_index
---@return integer hunk_offset
---@return integer cursor_row
---@return integer cursor_col
function PatchView:get_current_hunk()
  local cursor = vim.api.nvim_win_get_cursor(self.popup.winid)
  local index, offset = get_hunk(self._hunk_offsets, cursor[1])

  return index, offset, cursor[1], cursor[2]
end


---@return fun()
function PatchView:next_hunk_handler()
  return function()
    local hunk_idx, _, _, col = self:get_current_hunk()
    local new_row = self._hunk_offsets[hunk_idx+1]
    if hunk_idx + 1 == #self._hunk_offsets then
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
        new_row = self._hunk_offsets[hunk_idx-1]
      end
    end
    vim.api.nvim_win_set_cursor(self.popup.winid, { new_row, col })
  end
end


---@return string?
function PatchView:get_diff_hunk()
  local hunk_idx, _, _, _ = self:get_current_hunk()
  if hunk_idx > 0 and hunk_idx < #self._hunk_offsets then
    local hunk_lines = vim.api.nvim_buf_get_lines(
      self.popup.bufnr,
      self._hunk_offsets[hunk_idx] - 1, self._hunk_offsets[hunk_idx+1] - 1,
      true
    )
    local hunk_diff = self._hunk_diffs[hunk_idx]
    local _, partial_hunk = diff_utils.partial_hunk(hunk_diff, hunk_lines)

    local diff_lines = vim.list_extend(
      vim.list_slice(self._header), partial_hunk
    )
    return table.concat(diff_lines, "\n") .. "\n"
  end
end


---@return string?
function PatchView:get_diff_hunk_reversed()
  local hunk_idx, _, _, _ = self:get_current_hunk()
  if hunk_idx > 0 and hunk_idx < #self._hunk_offsets then
    local hunk_lines = vim.api.nvim_buf_get_lines(
      self.popup.bufnr,
      self._hunk_offsets[hunk_idx] - 1, self._hunk_offsets[hunk_idx+1] - 1,
      true
    )
    local hunk_diff = self._hunk_diffs[hunk_idx]
    local _, reversed_hunk = diff_utils.reverse_hunk(hunk_diff, hunk_lines)

    local diff_lines = vim.list_extend(vim.list_slice(self._header), reversed_hunk)
    return table.concat(diff_lines, "\n") .. "\n"
  end
end


---@param start_row integer
---@param end_row integer
---@param for_reverse boolean whether hunk range will be used for reverse later.
---@return GitDiffHunk[] hunk_diffs
---@return string[][] hunk_segments
function PatchView:_get_hunks_range(start_row, end_row, for_reverse)
  if start_row > end_row then
    start_row, end_row = end_row, start_row
  end

  local hunk_idx, hunk_offset = get_hunk(self._hunk_offsets, start_row)
  local next_offset = self._hunk_offsets[hunk_idx+1]

  local hunk_segments = {}
  local hunk_diffs = {}
  local hunk_lines = vim.api.nvim_buf_get_lines(
    self.popup.bufnr,
    hunk_offset - 1, next_offset - 1,
    true
  )
  local start_range = start_row - hunk_offset + 1
  local end_range = math.min(next_offset - 1, end_row) - hunk_offset + 1
  hunk_diffs[1], hunk_segments[1] = diff_utils.partial_hunk_selected(
    self._hunk_diffs[hunk_idx], hunk_lines,
    start_range, end_range,
    for_reverse
  )

  local i = #hunk_segments
  while next_offset < end_row do
    hunk_idx = hunk_idx + 1
    hunk_offset = next_offset
    next_offset = self._hunk_offsets[hunk_idx+1]
    i = i + 1

    hunk_lines = vim.api.nvim_buf_get_lines(
      self.popup.bufnr,
      hunk_offset - 1, next_offset - 1,
      true
    )
    if end_row >= next_offset then
      hunk_diffs[i], hunk_segments[i] = diff_utils.partial_hunk(self._hunk_diffs[hunk_idx], hunk_lines)
    else
      start_range = 1
      end_range = end_row - hunk_offset + 1
      hunk_diffs[i], hunk_segments[i] = diff_utils.partial_hunk_selected(
        self._hunk_diffs[hunk_idx], hunk_lines,
        start_range, end_range,
        for_reverse
      )
    end
  end

  return hunk_diffs, hunk_segments
end


---@param start_row integer
---@param end_row integer
---@param reverse boolean whether to get reverse diff
---@return string?
function PatchView:_get_diff_hunk_range(start_row, end_row, reverse)
  local hunk_diffs, hunk_segments = self:_get_hunks_range(start_row, end_row, reverse)
  if #hunk_segments == 0 or #hunk_diffs == 0 then
    return nil
  end

  if reverse then
    -- reverse hunks
    local reversed_hunk_diffs, reversed_hunk_segments = {}, {}
    for i = 1,#hunk_segments do
      local hunk, hunk_lines = diff_utils.reverse_hunk(hunk_diffs[i], hunk_segments[i])
      reversed_hunk_diffs[i] = hunk
      reversed_hunk_segments[i] = hunk_lines
    end
    hunk_diffs = reversed_hunk_diffs
    hunk_segments = reversed_hunk_segments
  end

  -- merge hunks
  local lines = diff_utils.merge_hunks(hunk_diffs, hunk_segments)
  for j, l in ipairs(self._header) do
    table.insert(lines, j, l)
  end
  return table.concat(lines, "\n") .. "\n"
end


---@param start_row integer
---@param end_row integer
---@return string?
function PatchView:get_diff_hunk_range(start_row, end_row)
  return self:_get_diff_hunk_range(start_row, end_row, false)
end

---@param start_row integer
---@param end_row integer
---@return string?
function PatchView:get_diff_hunk_range_reversed(start_row, end_row)
  return self:_get_diff_hunk_range(start_row, end_row, true)
end


return PatchView
