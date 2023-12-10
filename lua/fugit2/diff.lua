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


return M
