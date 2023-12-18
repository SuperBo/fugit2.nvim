---Diff helper module
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

  for line in vim.gsplit(patch, "\n", { plain=true, trimempty=true }) do
    local c = line:sub(1, 1)

    if c ~= "@" then
      if is_header then
        header[i] = line
      elseif current_hunk then
        -- insert to current hunk
        table.insert(current_hunk.lines, {
          c = c,
          text = line,
          linenr = i
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
    hunks  = hunks
  }
end

---Creates a patch just incude one hunk
---@param diff_header string[]
---@param hunk_header string
---@param hunk_lines string[]
---@return string
function M.partial_patch_from_hunk(diff_header, hunk_header, hunk_lines)
  local patch_lines = {}

  for i, line in ipairs(diff_header) do
    patch_lines[i] = line
  end

  patch_lines[#diff_header+1] = hunk_header

  for _, line in ipairs(hunk_lines) do
    table.insert(patch_lines, line)
  end

  table.insert(patch_lines, "") -- final empty line

  return table.concat(patch_lines, "\n")
end

---@param hunk_header string
---@return string
local function extract_hunk_header(hunk_header)
  local _, header_end = hunk_header:find("@@.+@@", 1, false)
  local header_text = ""
  if header_end then
    -- libgit2 header include newline
    header_text = hunk_header:sub(header_end+1, -2)
  end
  return header_text
end

---Converts a hunk in a patch line to appliable single hunk.
---@param hunk GitDiffHunk
---@param hunk_lines string[]
---@return string[]
function M.partial_hunk(hunk, hunk_lines)
  local header = string.format(
    "@@ -%d,%d +%d,%d @@%s",
    hunk.old_start, hunk.old_lines,
    math.max(hunk.old_start, 1), hunk.new_lines,
    extract_hunk_header(hunk.header)
  )

  local lines = { header }
  vim.list_extend(lines, hunk_lines, 2, #hunk_lines)
  return lines
end

---@param hunk GitDiffHunk
---@param hunk_lines string[] hunk content, including signature in the first line
---@return string[]
function M.reverse_hunk(hunk, hunk_lines)
  local reverse_header = string.format(
    "@@ -%d,%d +%d,%d @@%s",
    hunk.new_start, hunk.new_lines,
    hunk.old_start, hunk.old_lines,
    extract_hunk_header(hunk.header)
  )

  local lines = { reverse_header }
  for i=2,#hunk_lines do
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

  return lines
end


return M
