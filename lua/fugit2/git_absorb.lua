-- Module contains git absorb implementation
-- Adapt from https://github.com/tummychow/git-absorb

---@class GitAbsorbBlock
---@field start integer
---@field lines string[]
---@field trailing_newline boolean

---@class GitAbsorbHunk
---@field added GitAbsorbBlock
---@field deleted GitAbsorbBlock
local GitAbsorbHunk = {}
GitAbsorbHunk.__index = GitAbsorbHunk

-- =========
-- | Hunk  |
-- =========

---@param patch GitPatch
---@param idx integer
---@return GitAbsorbHunk?
---@return GIT_ERROR
function GitAbsorbHunk.from_patch(patch, idx)
  local hunk, err = patch:hunk(idx)
  if not hunk then
    return nil, err
  end

  local added_lines = {}
  local deleted_lines = {}
  local added_trailing_newline = true
  local deleted_trailing_newline = true

  for j = 0, patch:nhunks() - 1 do
    local line = patch:hunk_line(idx, j)
    if not line then
      break
    end
    if line.origin == "+" then
      added_lines[#added_lines + 1] = line.content
    elseif line.origin == "-" then
      deleted_lines[#deleted_lines + 1] = line.content
    elseif line.origin == ">" then
      deleted_trailing_newline = false
    elseif line.origin == "<" then
      added_trailing_newline = false
    end
  end

  if #added_lines ~= hunk.new_lines then
    return nil, -1
  end
  if #deleted_lines ~= hunk.old_lines then
    return nil, -1
  end

  ---@type GitAbsorbHunk
  local absorb_hunk = {
    added = {
      start = hunk.new_start,
      lines = added_lines,
      trailing_newline = added_trailing_newline,
    },
    deleted = {
      start = hunk.old_start,
      lines = deleted_lines,
      trailing_newline = deleted_trailing_newline,
    },
  }
  setmetatable(absorb_hunk, GitAbsorbHunk)
  return absorb_hunk, 0
end

-- Returns the unchanged lines around this hunk.
-- Any given hunk has four anchor points:
-- - the last unchanged line before it, on the removed side
-- - the first unchanged line after it, on the removed side
-- - the last unchanged line before it, on the added side
-- - the first unchanged line after it, on the added side
-- This function returns those four line numbers, in that order.
---@return integer deleted_before the last unchanged line before it, on the removed side
---@return integer deleted_after the first unchanged line after it, on the removed side
---@return integer added_before the last unchanged line before it, on the added side
---@return integer added_after the first unchanged line after it, on the added side
function GitAbsorbHunk:anchors()
  local deleted_len = #self.deleted.lines
  local added_len = #self.added.lines

  if deleted_len == 0 and added_len == 0 then
    return 0, 1, 0, 1
  elseif added_len == 0 then
    local d_start = self.deleted.start
    return d_start - 1, d_start + deleted_len, d_start - 1, d_start
  elseif deleted_len == 0 then
    local a_start = self.added.start
    return a_start - 1, a_start, a_start - 1, a_start + added_len
  end

  local d_start, a_start = self.deleted.start, self.added.start
  return d_start - 1, d_start + deleted_len, a_start, a_start + added_len
end

---Hunk clone
function GitAbsorbHunk:clone()
  local hunk = {
    added = vim.tbl_extend("keep", self.added),
    deleted = vim.tbl_extend("keep", self.deleted),
  }
  setmetatable(hunk, GitAbsorbHunk)
  return hunk
end

-- ===========
-- | Commute |
-- ===========

---Tests if all elements of the list are equal to each other.
---@param first_lines string[]
---@param second_lines string[]
---@return boolean uniform is uniform or not
local function uniform(first_lines, second_lines)
  local head = first_lines[1] or second_lines[1]
  if not head then
    return true
  end

  for i = 2, #first_lines do
    if first_lines[i] ~= head then
      return false
    end
  end

  for i = 1, #second_lines do
    if second_lines[i] ~= head then
      return false
    end
  end

  return true
end

---@param first GitAbsorbHunk
---@param second GitAbsorbHunk
---@return GitAbsorbHunk?
---@return GitAbsorbHunk?
local function commute(first, second)
  local _, _, first_upper, first_lower = first:anchors()
  local second_upper, second_lower, _, _ = second:anchors()

  -- represent hunks in content order rather than application order
  local first_above, above, below
  if first_lower <= second_upper then
    first_above, above, below = true, first, second
  elseif second_lower <= first_upper then
    first_above, above, below = false, second, first
  else
    -- if both hunks are exclusively adding or removing, and
    -- both hunks are composed entirely of the same line being
    -- repeated, then they commute no matter what their
    -- offsets are, because they can be interleaved in any
    -- order without changing the final result
    if
      (#first.added.lines == 0 and #second.added.lines == 0 and uniform(first.deleted.lines, second.deleted.lines))
      or (#first.deleted.lines == 0 and #second.deleted.lines == 0 and uniform(first.added.lines, second.added.lines))
    then
      return second:clone(), first:clone()
    end
    return nil, nil
  end

  local above_change_offset = (#above.added.lines - #above.deleted.lines) * (first_above and -1 or 1)

  local new_below = below:clone()
  new_below.added.start = below.added.start + above_change_offset
  new_below.deleted.start = below.deleted.start + above_change_offset

  if first_above then
    return new_below, above:clone()
  else
    return above:clone(), new_below
  end
end

local M = {}
M.commute = commute

return M
