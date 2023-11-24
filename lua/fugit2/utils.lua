---@class Fugit2Utils
local M = {}


---@param base_path string Base dir
---@param path string Input path to make relative
---@return string
function M.make_relative_path(base_path, path)
  if base_path == path then
    return "."
  end

  local stop = false
  local relbase = ""
  local relpath = path
  local base_depth, path_depth = 0, 0
  for dir in vim.gsplit(base_path, "/", { plain = true }) do
    if not stop and vim.startswith(relpath, dir .. "/") then
      relpath = relpath:sub(#dir+2, -1)
      relbase = relbase .. "/" .. dir
      path_depth = path_depth + 1
    else
      stop = true
    end
    base_depth = base_depth + 1
  end

  if path_depth < base_depth then
    relpath = string.rep("../", base_depth - path_depth) .. relpath
  end

  return relpath
end


return M
