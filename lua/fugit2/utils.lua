local git2 = require "fugit2.git2"

---@class Fugit2Utils
local M = {}


-- Return relative path with given base_path
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


-- Returns git remote icon
---@param url string
---@return string
function M.get_git_icon(url)
  local hostname = url:match("git@([^ /:]+)")
  if not hostname then
    hostname = url:match("https?://([^ /]+)")
  end

  if hostname then
    if hostname:find("gitlab") then
      return "󰮠 "
    elseif hostname:find("github") then
      return "󰊤 "
    elseif hostname:find("bitbucket") then
      return "󰂨 "
    end
  end
  return "󰊢 "
end


-- Returns git namespace icon
---@param namespace GIT_REFERENCE_NAMESPACE
---@return string
function M.get_git_namespace_icon(namespace)
  if namespace == git2.GIT_REFERENCE_NAMESPACE.BRANCH then
    return "󰘬 "
  elseif namespace == git2.GIT_REFERENCE_NAMESPACE.TAG then
    return "󰓹 "
  elseif namespace == git2.GIT_REFERENCE_NAMESPACE.REMOTE then
    return "󰑔 "
  end

  return ""
end


return M
