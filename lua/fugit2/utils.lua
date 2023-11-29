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



---@class BitArray BitArray in big-endian representation
---@field n integer length of bitarray
---@field buf integer bitarray buffer
local BitArray = {}
BitArray.__index = BitArray


---@return BitArray
function BitArray.new()
  local arr = { n = 0, buf = 0ULL }
  setmetatable(arr, BitArray)
  return arr
end


---@param set boolean whether new bit is set or not
---@return integer length new lenght of array
function BitArray:append(set)
  local buf = bit.lshift(self.buf, 1)
  if set then
    buf = bit.bor(buf, 1)
  end
  self.buf = buf
  self.n = self.n + 1

  return self.n
end


-- Pops last entry in bitarray.
---@return boolean?
function BitArray:pop()
  if self.n <= 0 then
    return nil
  end
  self.n = self.n - 1

  local val = bit.band(self.buf, 1)
  self.buf = bit.rshift(self.buf, 1)

  return val ~= 0
end

---@return BitArray
function BitArray:copy()
  local a = BitArray.new()
  a.n = self.n
  a.buf = self.buf
  return a
end

-- Sets n-th bit in bitarray (1-based index)
---@param i integer index to set bit
---@return BitArray
function BitArray:set(i)
  if i > 0 and i <= self.n then
    self.buf = bit.bor(self.buf, bit.lshift(1, self.n - i))
  end
  return self
end

-- Unset n-th bit in bitarray (1-based index)
---@param i integer index to set bit
---@return BitArray
function BitArray:unset(i)
  if i > 0 and i <= self.n then
    local mask = bit.bnot(bit.lshift(1, self.n - i))
    self.buf = bit.band(self.buf, mask)
  end
  return self
end


---@param arr BitArray
---@param is_set boolean Whether to get set or unset indices in bitarray
---@return integer[] indices of set/unset indices (1-based)
local function _bitarray_get_indices(arr, is_set)
  ---@type integer
  local i, mask = 1, bit.lshift(1, arr.n - 1)
  ---@type boolean
  local b
  local indices = {}

  while i <= arr.n do
    b = bit.band(arr.buf, mask) ~= 0
    -- logical exclusive or
    if is_set and b or not (is_set or b) then
      table.insert(indices, i)
    end

    i = i + 1
    mask = bit.rshift(mask, 1)
  end

  return indices
end


-- Get set indices in bitmap
---@return integer[] set List of set indicies (1-based)
function BitArray:get_set_indices()
  return _bitarray_get_indices(self, true)
end


-- Gets unset indices in bitmap
---@return integer[] unset List of unset indices (1-based)
function BitArray:get_unset_indices()
  return _bitarray_get_indices(self, false)
end


-- Gets unset indices (1-based) and set it
---@return integer[] unset List of unset indices (1-based)
function BitArray:set_unset_indices()
  ---@type integer
  local i, mask = self.n, 1
  local unset = {}

  while i > 0 do
    if bit.band(self.buf, mask) == 0 then
      self.buf = bit.bor(self.buf, mask)
      table.insert(unset, 1, i)
    end

    i = i - 1
    mask = bit.lshift(mask, 1)
  end

  return unset
end


-- Gets first k unset indices (1-based) and set it
-- k can be > #number of unset bit in bitarray.
-- If k > # number of unset bit, bitaray will be appended.
---@param k integer
---@return integer[] unset List of unset indices (1-based) have just been set.
function BitArray:set_k_unset_indices(k)
  ---@type integer
  local i, n = 1, 0
  ---@type integer
  local mask = bit.lshift(1, self.n - 1)
  local unset = {}

  while i <= self.n and n < k do
    if bit.band(self.buf, mask) == 0 then
      self.buf = bit.bor(self.buf, mask)
      table.insert(unset, i)
      n = n + 1
    end

    i = i + 1
    mask = bit.rshift(mask, 1)
  end

  if n < k then
    local delta = k - n
    local b_append = bit.lshift(1, delta) - 1
    self.buf = bit.bor(bit.lshift(self.buf, delta), b_append)
    self.n = self.n + delta

    while n < k do
      table.insert(unset, i)
      i = i + 1
      n = n + 1
    end
  end

  return unset
end


M.BitArray = BitArray


return M
