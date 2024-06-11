---Diff helper module

local table_new = require "table.new"

---@module 'Fugit2DiffHelper'
local M = {}

---@alias Fugit2HunkLine { c: string, text: string, linenr: integer }
---@alias Fugit2HunkItem { header: string, linenr: integer, lines: Fugit2HunkLine[] }

---Parses a patch text to hunks and patch header
---@param patch string Patch as as tring
---@return { header: string[], hunks: Fugit2HunkItem[] }
function M.parse_patch(patch)
  local i, is_header = 1, true
  local header = {}
  local hunks = {}
  local current_hunk = nil

  for line in vim.gsplit(patch, "\n", { plain = true, trimempty = true }) do
    local c = line:sub(1, 1)

    if c ~= "@" then
      if is_header then
        header[i] = line
      elseif current_hunk then
        -- insert to current hunk
        table.insert(current_hunk.lines, {
          c = c,
          text = line,
          linenr = i,
        })
      end
    else
      is_header = false
      -- add new hunk
      if current_hunk then
        table.insert(hunks, current_hunk)
      end
      current_hunk = { header = line, linenr = i, lines = {} }
    end

    i = i + 1
  end

  -- for last hunk
  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  return {
    header = header,
    hunks = hunks,
  }
end

---Creates a patch just include one hunk
---@param diff_header string[]
---@param hunk_header string
---@param hunk_lines string[]
---@return string
function M.partial_patch_from_hunk(diff_header, hunk_header, hunk_lines)
  local patch_lines = {}

  for i, line in ipairs(diff_header) do
    patch_lines[i] = line
  end

  patch_lines[#diff_header + 1] = hunk_header

  for _, line in ipairs(hunk_lines) do
    table.insert(patch_lines, line)
  end

  table.insert(patch_lines, "") -- final empty line

  return table.concat(patch_lines, "\n")
end

local HUNK_HEADER_STRING = "@@ -%d,%d +%d,%d @@%s"

---@param hunk_header string
---@return string
local function extract_hunk_header(hunk_header)
  local _, header_end = hunk_header:find("@@.+@@", 1, false)
  local header_text = ""
  if header_end then
    -- libgit2 header include newline
    header_text = hunk_header:sub(header_end + 1, -2)
  end
  return header_text
end

---Format a GitDiffHunk to string
---@param hunk GitDiffHunk
local function diff_hunk_header(hunk)
  return string.format(
    HUNK_HEADER_STRING,
    hunk.old_start,
    hunk.old_lines,
    hunk.new_start,
    hunk.new_lines,
    extract_hunk_header(hunk.header)
  )
end

---Converts a hunk in a patch line to appliable single hunk.
---@param hunk GitDiffHunk
---@param hunk_lines string[]
---@return GitDiffHunk new_hunk
---@return string[]
function M.partial_hunk(hunk, hunk_lines)
  ---@type GitDiffHunk
  local new_hunk = {
    header = hunk.header,
    num_lines = hunk.num_lines,
    old_start = hunk.old_start,
    old_lines = hunk.old_lines,
    new_start = math.max(hunk.old_start, 1),
    new_lines = hunk.new_lines,
  }

  local lines = { diff_hunk_header(new_hunk) }
  vim.list_extend(lines, hunk_lines, 2, #hunk_lines)
  return new_hunk, lines
end

---@param hunk GitDiffHunk
---@param hunk_lines string[] hunk content, including signature in the first line
---@return GitDiffHunk new_hunk
---@return string[]
function M.reverse_hunk(hunk, hunk_lines)
  ---@type GitDiffHunk
  local new_hunk = {
    num_lines = hunk.num_lines,
    header = hunk.header,
    old_start = hunk.new_start,
    old_lines = hunk.new_lines,
    new_start = hunk.old_start > 0 and hunk.new_start or 0,
    new_lines = hunk.old_lines,
  }

  local lines = { diff_hunk_header(new_hunk) }
  for i = 2, #hunk_lines do
    local line = hunk_lines[i]
    local char = line:sub(1, 1)
    if char == "+" then
      lines[i] = "-" .. line:sub(2, -1)
    elseif char == "-" then
      lines[i] = "+" .. line:sub(2, -1)
    else
      lines[i] = line
    end
  end

  return new_hunk, lines
end

---Creates a partial hunk with selected lines.
---@param hunk GitDiffHunk
---@param hunk_lines string[]
---@param start_hunk_line integer start hunk line(inclusive)
---@param line_add_as_context boolean Treat non-selected add line as context. If false, minus line is treated as context..
---@param end_hunk_line integer end hunk line (inclusive)
---@return GitDiffHunk? new_hunk
---@return string[]?
function M.partial_hunk_selected(hunk, hunk_lines, start_hunk_line, end_hunk_line, line_add_as_context)
  if start_hunk_line > end_hunk_line or start_hunk_line > #hunk_lines or end_hunk_line < 1 then
    return nil, nil
  end

  local old_lines, new_lines = 0, 0
  local lines = {}

  for i = 2, start_hunk_line - 1 do
    local line = hunk_lines[i]
    local char = line:sub(1, 1)
    if char == " " or (line_add_as_context and char == "+" or char == "-") then
      old_lines = old_lines + 1
      new_lines = new_lines + 1
      if char == " " then
        lines[#lines + 1] = line
      else
        lines[#lines + 1] = " " .. line:sub(2)
      end
    end
  end

  local num_add, num_minus = 0, 0
  for i = start_hunk_line, end_hunk_line do
    local line = hunk_lines[i]
    local char = line:sub(1, 1)
    if char == " " then
      old_lines = old_lines + 1
      new_lines = new_lines + 1
      lines[#lines + 1] = line
    elseif char == "+" then
      num_add = num_add + 1
      lines[#lines + 1] = line
    elseif char == "-" then
      num_minus = num_minus + 1
      lines[#lines + 1] = line
    end
  end

  if num_minus + num_add == 0 then
    -- no changes
    return nil, nil
  end

  new_lines = new_lines + num_add
  old_lines = old_lines + num_minus

  local num_context = 0
  for i = end_hunk_line + 1, #hunk_lines do
    local line = hunk_lines[i]
    local char = line:sub(1, 1)
    if char == " " or (line_add_as_context and char == "+" or char == "-") then
      num_context = num_context + 1
      old_lines = old_lines + 1
      new_lines = new_lines + 1

      if char == " " then
        lines[#lines + 1] = line
      else
        lines[#lines + 1] = " " .. line:sub(2)
      end

      if num_context == 3 then
        break
      end
    end
  end

  ---@type GitDiffHunk
  local new_hunk = {
    header = hunk.header,
    old_start = hunk.old_start,
    old_lines = old_lines,
    new_start = math.max(hunk.old_start, 1),
    new_lines = new_lines,
    num_lines = #lines + 1,
  }
  table.insert(lines, 1, diff_hunk_header(new_hunk))

  return new_hunk, lines
end

---@param hunk_diffs GitDiffHunk[]
---@param hunk_segments string[][]
---@return string[] lines lines of merged string
function M.merge_hunks(hunk_diffs, hunk_segments)
  local lines = {}
  local line_delta = 0
  for i = 1, #hunk_diffs do
    local hunk = hunk_diffs[i]
    local hunk_lines = hunk_segments[i]
    ---@type GitDiffHunk
    local new_hunk = {
      num_lines = hunk.num_lines,
      header = hunk.header,
      old_start = hunk.old_start,
      old_lines = hunk.old_lines,
      new_start = hunk.new_start + line_delta,
      new_lines = hunk.new_lines,
    }
    line_delta = line_delta + hunk.new_lines - hunk.old_lines

    lines[#lines + 1] = diff_hunk_header(new_hunk)
    vim.list_extend(lines, hunk_lines, 2, #hunk_lines)
  end

  return lines
end

-- Find line in file from hunk
---@param hunk GitDiffHunk hunk information
---@param hunk_lines string[] hunk content, including header in the first line
---@param offset integer offset from start of hunk header
---@return integer liner line in original file
function M.file_line(hunk, hunk_lines, offset)
  local linenr = hunk.new_start

  local is_prev_minus = false
  local n = math.min(offset + 1, #hunk_lines)
  for i = 3, n do
    local char = hunk_lines[i]:sub(1, 1)

    if not is_prev_minus then
      linenr = linenr + 1
    end

    is_prev_minus = (char == "-") and true or false
  end

  return linenr
end

-- Numbering hunk lines
---@param hunk GitDiffHunk hunk info
---@param hunk_lines string[] hunk lines
---@return integer[] line_numbers line number in file
function M.numbering_hunk_lines(hunk, hunk_lines)
  local numbers = table_new(#hunk_lines, 0)
  numbers[1] = 0 -- line number of header is 0
  local linenr, linenr_before_minus = hunk.new_start, hunk.new_start
  local is_prev_minus = false
  for i = 2, #hunk_lines do
    local is_minus = (hunk_lines[i]:sub(1, 1) == "-")
    if not is_minus then
      if is_prev_minus then
        linenr = linenr_before_minus + 1
      end

      linenr_before_minus = linenr
    end

    numbers[i] = linenr

    linenr = linenr + 1
    is_prev_minus = is_minus
  end

  return numbers
end

-- Select hunk lines in hunk defined by range
---@param hunk GitDiffHunk
---@param hunk_lines string[]
---@param start_linenr integer start line number of selection
---@param num_lines integer number of lines selected
---@return string[]? selected_lines
function M.select_hunk_lines(hunk, hunk_lines, start_linenr, num_lines)
  local end_linenr = start_linenr + num_lines - 1
  local hunk_end_linenr = hunk.new_start + hunk.new_lines - 1
  if end_linenr < hunk.new_start or hunk_end_linenr < start_linenr then
    return nil
  end

  local lines = {}
  local linenr, linenr_before_minus = hunk.new_start, hunk.new_start
  local is_prev_minus = false
  for i = 2, #hunk_lines do
    local is_minus = (hunk_lines[i]:sub(1, 1) == "-")
    if not is_minus then
      if is_prev_minus then
        linenr = linenr_before_minus + 1
      end
      linenr_before_minus = linenr
    end

    if linenr >= start_linenr and linenr <= end_linenr then
      lines[#lines + 1] = hunk_lines[i]
    end

    if not is_minus and linenr == end_linenr then
      break
    end

    linenr = linenr + 1
    is_prev_minus = is_minus
  end

  return lines
end

-- Convert patch string to lines of header and contents
---@param patch string patch content as string
---@return string[] header header lines
---@return string[] hunks hunk lines
function M.split_patch(patch)
  local lines = vim.split(patch, "\n", { plain = true, trimempty = true })
  local header = {}

  for i, l in ipairs(lines) do
    if l:sub(1, 1) ~= "@" then
      header[i] = l
    else
      break
    end
  end

  local hunks = vim.list_slice(lines, #header + 1)

  return header, hunks
end

-- Filters patch lines based on indices
---@param hunk_lines string[] patch lines without header
---@param hunks GitDiffHunk[] hunks info
---@param indices integer[] indices of selected hunks.
---@return string[] sub_patch_lines return patch lines corressponding to selected indices
---@return GitDiffHunk[] sub_hunks return sub hunks corressponding to selected indices
function M.patch_sub_lines(hunk_lines, hunks, indices)
  if #indices < 1 then
    return hunk_lines, hunks
  end

  local sub_lines = {}
  local sub_hunks = table_new(#indices, 0)
  local j, find_i = 1, indices[1]
  local linenr = 1
  for i, hunk in ipairs(hunks) do
    if i == find_i then
      vim.list_extend(sub_lines, hunk_lines, linenr, linenr + hunk.num_lines)
      sub_hunks[#sub_hunks + 1] = hunk
      j = j + 1
      if j > #indices then
        break
      end
      find_i = indices[j]
    end
    linenr = linenr + hunk.num_lines + 1
  end

  return sub_lines, sub_hunks
end

return M
