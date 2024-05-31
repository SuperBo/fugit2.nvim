-- Helper module to parse git blame porcelain information

local M = {}

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
          author_name = "You",
          author_email = "not@committed.yet",
          committer_name = "You",
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

return M
