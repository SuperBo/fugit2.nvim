-- Helper module to parse git blame porcelain information

local diff_utils = require "fugit2.diff"
local git2 = require "fugit2.git2"
local pendulum = require "fugit2.core.pendulum"
local utils = require "fugit2.utils"

pendulum.init()

---@module 'Fugit2BlameHelper'
local M = {}

---@class Fugit2GitBlameCommit
---@field oid string
---@field message_header string
---@field message_body string
---@field hunks GitDiffHunk[]?
---@field patch string[]?

---@class Fugit2GitBlameHunk
---@field oid string Git oid string
---@field author_name string author name
---@field author_email string author email
---@field committer_name string committer name
---@field committer_email string committer email
---@field committer_tz string committer timezone
---@field date osdateparam?
---@field message string
---@field num_lines integer
---@field start_linenr integer final start line number
---@field orig_start_linenr integer original start linenumber
---@field orig_path string? original file name if have

-- Parse result from `git blame --porcelain --date=unix`
---@param stdout string
---@return Fugit2GitBlameHunk[] hunks from git blame
function M.parse_git_blame_porcelain(stdout)
  local blame_lines = vim.split(stdout, "\n", { plain = true })
  return M.parse_git_blame_porcelain_lines(blame_lines)
end

-- Parse result from `git blame --porcelain --date=unix`
-- Receives inputs as array of string
---@param blame_lines string[] output from stdout of git blame command
---@return Fugit2GitBlameHunk[] hunks from git blame
function M.parse_git_blame_porcelain_lines(blame_lines)
  local opts = { plain = true }

  -- map from oid to first seen hunk
  local hunk_oid = {} --[[@as { [string]: Fugit2GitBlameHunk } ]]
  local hunks = {} --[[@as Fugit2GitBlameHunk[] ]]

  local i = 1
  while i <= #blame_lines do
    local oid_line = blame_lines[i]
    local oid_parts = vim.split(oid_line, " ", opts)

    if #oid_parts < 4 then
      -- a line in an already processed hunk
      -- skip to 2 next line
      i = i + 2
      goto parse_git_blame_continue
    end

    local oid = oid_parts[1]
    local orig_linenr = tonumber(oid_parts[2]) or 1
    local linenr = tonumber(oid_parts[3]) or 1
    local num_lines = tonumber(oid_parts[4]) or 0

    local next_line = blame_lines[i + 1]
    if next_line:sub(1, 1) == "\t" then
      -- this commit id has been seen before
      local prev_hunk = hunk_oid[oid]
      if prev_hunk then
        local hunk = {
          oid = oid,
          author_name = prev_hunk.author_name,
          author_email = prev_hunk.author_email,
          committer_name = prev_hunk.committer_name,
          committer_email = prev_hunk.comitter_email,
          committer_tz = prev_hunk.committer_tz,
          message = prev_hunk.message,
          num_lines = num_lines,
          start_linenr = linenr,
          orig_start_linenr = orig_linenr,
          orig_path = prev_hunk.orig_path,
          date = prev_hunk.date,
        } --[[@as Fugit2GitBlameHunk]]
        hunks[#hunks + 1] = hunk
      end

      i = i + 2
    else
      -- parse commit information
      local date = os.date("*t", tonumber(blame_lines[i + 3]:sub(string.len "author-time " + 1)))
      local message = ""
      local orig_path

      local j = i + 9
      local sub_line = blame_lines[j]
      repeat
        if vim.startswith(sub_line, "summary ") then
          message = sub_line:sub(string.len "summary " + 1)
        elseif vim.startswith(sub_line, "filename ") then
          orig_path = sub_line:sub(string.len "filename " + 1)
        end
        j = j + 1
        sub_line = blame_lines[j]
      until sub_line:sub(1, 1) == "\t"

      if oid:sub(1, 16) == "0000000000000000" then
        -- null commit, not committed yet
        local hunk = {
          oid = oid,
          author_name = "Uncommitted",
          author_email = "not@committed.yet",
          committer_name = "Uncommitted",
          committer_email = "not@committed.yet",
          committer_tz = "+0000",
          message = "Uncommitted changes",
          num_lines = num_lines,
          start_linenr = linenr,
          orig_start_linenr = orig_linenr,
        } --[[@as Fugit2GitBlameHunk]]
        hunks[#hunks + 1] = hunk
        hunk_oid[oid] = hunk
      else
        local hunk = {
          oid = oid,
          author_name = next_line:sub(string.len "author " + 1),
          author_email = vim.split(blame_lines[i + 2], " ", opts)[2],
          committer_name = blame_lines[i + 5]:sub(string.len "committer " + 1),
          committer_email = vim.split(blame_lines[i + 6], " ", opts)[2],
          committer_tz = vim.split(blame_lines[i + 8], " ", opts)[2],
          message = message,
          num_lines = num_lines,
          start_linenr = linenr,
          orig_start_linenr = orig_linenr,
          orig_path = orig_path,
          date = date --[[@as osdateparam]],
        } --[[@as Fugit2GitBlameHunk]]
        hunks[#hunks + 1] = hunk
        hunk_oid[oid] = hunk
      end
      i = j + 1
    end

    ::parse_git_blame_continue::
  end

  return hunks
end

-- Converts commit time to ago string and age color index.
---@param date osdateparam input date
---@param today osdateparam? current date time
---@return string ago string such as "3 years ago"
---@return integer age_color in range [1, 10], 10 is latest, 1 is oldest
function M.blame_time(date, today)
  local now = today or os.date "*t" --[[@as osdateparam]]
  local time_ago = "a moment ago"
  local age_color = 10 -- latest

  local diff = pendulum.precise_diff(now, date)
  time_ago = diff:ago()

  local weeks = diff:in_weeks()
  if diff.years > 1 then
    age_color = 1
  elseif diff.years == 1 then
    age_color = 2
  elseif diff.months > 6 then
    age_color = 3
  elseif diff.months > 3 then
    age_color = 4
  elseif diff.months > 1 then
    age_color = 5
  elseif diff.months == 1 then
    age_color = 6
  elseif weeks > 2 then
    age_color = 7
  elseif weeks >= 2 then
    age_color = 8
  elseif weeks == 1 then
    age_color = 9
  end

  return time_ago, age_color
end

-- Filters blame hunk and patch hunk
-- Only keeping patch hunk that intersects with blam hunks
---@param hunks GitDiffHunk[]
---@param blame_ranges Fugit2GitBlameRange[]
---@return integer[] indices index of remaining hunks
function M.filter_intersect_hunks(hunks, blame_ranges)
  local i, j = 1, 1
  local intersect_indices = {}
  local last_i = 0

  while i <= #hunks and j <= #blame_ranges do
    local diff_hunk = hunks[i]
    local blame_range = blame_ranges[j]

    local diff_end = diff_hunk.new_start + diff_hunk.new_lines
    local blame_end = blame_range.start + blame_range.num

    if
      diff_hunk.new_start < (blame_range.start + blame_range.num)
      and blame_range.start < (diff_hunk.new_start + diff_hunk.new_lines)
    then
      -- intersect
      if i ~= last_i then
        -- dedup indices
        intersect_indices[#intersect_indices + 1] = i
      end
      last_i = i
    end

    if diff_end == blame_end then
      i = i + 1
      j = j + 1
    elseif diff_end < blame_end then
      i = i + 1
    else
      j = j + 1
    end
  end

  return intersect_indices
end

-- Find the first intersect hunk from hunk items
---@param hunks GitDiffHunk[] patch hunks, can be filtered by filter_intersect_hunks
---@param patch_lines string[] patch splitted into lines
---@param start_linenr integer start line of range
---@param num_lines integer num lines of range
---@return GitDiffHunk? hunk information of founded hunk
---@return string[]? lines intersect lines from patch lines
function M.find_intersect_hunk(hunks, patch_lines, start_linenr, num_lines)
  if #hunks < 1 or #patch_lines < 1 then
    return nil, nil
  end

  local offsets = utils.list_new(#hunks)
  for i, h in ipairs(hunks) do
    offsets[i] = h.new_start
  end

  local hunk_idx, _ = utils.get_hunk(offsets, start_linenr)
  if hunk_idx < 1 or hunk_idx > #hunks then
    return nil, nil
  end

  for i = hunk_idx, math.min(hunk_idx + 1, #hunks) do
    local hunk = hunks[i]

    if hunk.new_start < (start_linenr + num_lines) and start_linenr < (hunk.new_start + hunk.new_lines) then
      -- intersect
      local hunk_linenr = 1
      for j = 1, i - 1 do
        hunk_linenr = hunk_linenr + hunks[j].num_lines + 1 -- one extra line of header
      end
      local hunk_lines = vim.list_slice(patch_lines, hunk_linenr, hunk_linenr + hunk.num_lines)

      local intersect_lines = diff_utils.select_hunk_lines(hunk, hunk_lines, start_linenr, num_lines)
      return hunk, intersect_lines
    end
  end

  return nil, nil
end

-- Get blame commit details including diff, commit info
---@param repo GitRepository
---@param oid_str string git commit id full string
---@param blame_ranges Fugit2GitBlameRange[]?
---@return Fugit2GitBlameCommit?
---@return GIT_ERROR
function M.blame_commit_detail(repo, oid_str, file_path, blame_ranges)
  local oid, err = git2.ObjectId.from_string(oid_str)
  if not oid then
    return nil, err
  end
  local commit
  commit, err = repo:commit_lookup(oid)
  if not commit then
    return nil, err
  end

  ---@type Fugit2GitBlameCommit
  local blame_detail = {
    oid = oid_str:sub(1, 8),
    message_header = commit:summary(),
    message_body = commit:body(),
  }

  local diff, parent_commit, patches
  if commit:nparents() > 0 then
    parent_commit, err = commit:parent(0)
  end

  diff, err = repo:diff_commit_to_commit(parent_commit, commit, { file_path }, 3)
  if not diff then
    return blame_detail, err
  end

  patches, err = diff:patches(false)
  if #patches == 0 then
    return blame_detail, err
  end

  local patch = patches[1]
  local hunk_info = utils.list_new(patch.num_hunks)
  for i = 0, patch.num_hunks - 1 do
    hunk_info[i + 1], _ = patch.patch:hunk(i)
  end

  local _, hunk_lines = diff_utils.split_patch(tostring(patch.patch))

  if not blame_ranges or #blame_ranges < 0 then
    blame_detail.hunks = hunk_info
    blame_detail.patch = hunk_lines
    return blame_detail, 0
  end

  -- filter intersect hunks if blame_ranges is provided
  local indices = M.filter_intersect_hunks(hunk_info, blame_ranges)
  local sub_lines, sub_hunks = diff_utils.patch_sub_lines(hunk_lines, hunk_info, indices)

  blame_detail.hunks = sub_hunks
  blame_detail.patch = sub_lines
  return blame_detail, 0
end

return M
