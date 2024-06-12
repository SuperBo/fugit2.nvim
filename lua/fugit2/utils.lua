local table_clear = require "table.clear"

local NuiLine = require "nui.line"
local NuiText = require "nui.text"
local NuiTree = require "nui.tree"
local Path = require "plenary.path"

---@class Fugit2Utils
local M = {}

-- copy from git2 to avoid import
local GIT_REFERENCE_NAMESPACE = {
  NONE = 0, -- Normal ref, no namespace
  BRANCH = 1, -- Reference is in Branch namespace
  TAG = 2, -- Reference is in Tag namespace
  REMOTE = 3, -- Reference is in Remote namespace
  NOTE = 4, -- Reference is in Note namespace
}

---@enum LINUX_SIGNALS
M.LINUX_SIGNALS = {
  SIGHUP = 1,
  SIGQUIT = 3,
  SIGINT = 2,
  SIGABRT = 6,
  SIGKILL = 9,
  SIGTERM = 15,
}

---@type string
M.KEY_ESC = vim.api.nvim_replace_termcodes("<esc>", true, false, true)

-- temp dir
M.TMPDIR = Path:new(os.getenv "TMPDIR" or "/tmp")

M.LOADING_CHARS = {
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
}

---@param str string
function M.lines_head(str)
  local newline = str:find("\n", 1, true)
  if newline then
    return str:sub(1, newline - 1)
  end
  return str
end

-- Pretty print lines to debug
---@param str string
function M.lines_print(str)
  for line in vim.gsplit(str, "\n", { plain = true }) do
    if line:len() > 0 then
      print(line)
    else
      print "--newline--"
    end
  end
end

-- Rounding a number
---@param n number
---@return number
function M.round(n)
  return math.floor(n + 0.5)
end

---@param str string
---@return NuiLine
function M.message_title_prettify(str)
  local title = M.lines_head(str)

  local prefix = title:find(":", 1, true) or title:find("]", 1, true)
  if prefix then
    return NuiLine {
      NuiText(title:sub(1, prefix), "bold"),
      NuiText(title:sub(prefix + 1, -1)),
    }
  end

  prefix = title:find("^Merge", 1, false)
  if prefix then
    return NuiLine {
      NuiText(title:sub(1, 5), "bold"),
      NuiText(title:sub(6, -1)),
    }
  end

  return NuiLine { NuiText(title) }
end

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
      relpath = relpath:sub(#dir + 2, -1)
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
  local hostname = url:match "git@([^ /:]+)"
  if not hostname then
    hostname = url:match "https?://([^ /]+)"
  end

  if hostname then
    if hostname:find "gitlab" then
      return "󰮠 "
    elseif hostname:find "github" then
      return "󰊤 "
    elseif hostname:find "bitbucket" then
      return "󰂨 "
    end
  end
  return "󰊢 "
end

-- Returns git namespace icon
---@param namespace GIT_REFERENCE_NAMESPACE
---@return string
function M.get_git_namespace_icon(namespace)
  if namespace == GIT_REFERENCE_NAMESPACE.BRANCH then
    return "󰘬 "
  elseif namespace == GIT_REFERENCE_NAMESPACE.TAG then
    return "󰓹 "
  elseif namespace == GIT_REFERENCE_NAMESPACE.REMOTE then
    return "󰑔 "
  end

  return ""
end

local _GIT_DELTA_ICONS = {
  "󰆢 ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  " ",
  nil,
  " ",
  " ",
}

-- Returns git status icon
---@param status GIT_DELTA
---@param default string return icon when no match
---@return string
function M.get_git_status_icon(status, default)
  return _GIT_DELTA_ICONS[status + 1] or default
end

---Return ahead behind string
---@param ahead integer?
---@param behind integer?
---@return string
function M.get_ahead_behind_text(ahead, behind)
  local str = ""
  if ahead and ahead > 0 then
    str = "↑" .. ahead
  end
  if behind and behind > 0 then
    str = str .. "↓" .. behind
  end
  return str
end

---Build directory tree from a list of paths.
---@generic T
---@param path_fn fun(val: T): string function which returns path-like string from ele, e.g: a/b/c.txt
---@param lst T[] list of data from that can get path
---@alias Fugit2DirectoryNode { [string]: T | Fugit2DirectoryNode }
---@return Fugit2DirectoryNode
function M.build_dir_tree(path_fn, lst)
  local dir_tree = {}

  for _, ele in ipairs(lst) do
    local path = path_fn(ele)
    local dirname = vim.fs.dirname(path)

    local dir = dir_tree
    if dirname ~= "" and dirname ~= "." then
      for s in vim.gsplit(dirname, "/", { plain = true }) do
        if dir[s] then
          dir = dir[s]
        else
          dir[s] = {}
          dir = dir[s]
        end
      end
    end

    if dir["."] then
      table.insert(dir["."], ele)
    else
      dir["."] = { ele }
    end
  end

  return dir_tree
end

---@generic T
---@param node_fn fun(val: T): NuiTree.Node function which returns node from T.
---@param dir_tree Fugit2DirectoryNode dir tree built from build_dir_tree
---@return NuiTree.Node[]
function M.build_nui_tree_nodes(node_fn, dir_tree)
  local function construct_tree_nodes(dir_sub_tree, prefix)
    local files = {}
    local dir_idx = 1 -- index to insert directory
    for k, v in pairs(dir_sub_tree) do
      if k == "." then
        for _, f in ipairs(v) do
          table.insert(files, node_fn(f))
        end
      else
        local id = prefix .. "/" .. k
        local children = construct_tree_nodes(v, id)
        local node = NuiTree.Node({ text = k, id = id }, children)
        node:expand()
        table.insert(files, dir_idx, node)
        dir_idx = dir_idx + 1
      end
    end

    return files
  end

  return construct_tree_nodes(dir_tree, "")
end

-- Random utils
local id_counter = 0ULL
local id_random = math.random(0, 255)

---@return integer id time-based unique id
function M.new_pid()
  local id = bit.bor(bit.lshift(id_counter, 8), id_random)
  id_counter = id_counter + 1
  return id
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
---@return integer length new length of array
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
    self.buf = bit.bor(self.buf, bit.lshift(1ULL, self.n - i))
  end
  return self
end

-- Unset n-th bit in bitarray (1-based index)
---@param i integer index to set bit
---@return BitArray
function BitArray:unset(i)
  if i > 0 and i <= self.n then
    local mask = bit.bnot(bit.lshift(1ULL, self.n - i))
    self.buf = bit.band(self.buf, mask)
  end
  return self
end

---@param arr BitArray
---@param is_set boolean Whether to get set or unset indices in bitarray
---@return integer[] indices of set/unset indices (1-based)
local function _bitarray_get_indices(arr, is_set)
  ---@type integer
  local i, mask = 1, bit.lshift(1ULL, arr.n - 1)
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
  local i, mask = self.n, 1ULL
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
  local mask = bit.lshift(1ULL, self.n - 1)
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
    local b_append = bit.lshift(1ULL, delta) - 1
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

-- ====================
-- | Table/list utils |
-- ====================

---@param n integer number of element in list
function M.list_new(n)
  return require "table.new"(n, 0)
end

---Builds a lookup table for a given list.
---@generic T
---@param lst T[]
---@param key_fn fun(ele: T): string
---@return { [string]: T }
function M.list_build_lookup(key_fn, lst)
  local lookup = {}

  for _, v in ipairs(lst) do
    lookup[key_fn(v)] = v
  end

  return lookup
end

---Inserts new element into a sorted list, return a sorted list.
---@generic T
---@param lst T[]
---@param ele number
---@return T[]
function M.list_sorted_insert(lst, ele)
  local i = 1
  while i < #lst + 1 and ele > lst[i] do
    i = i + 1
  end
  table.insert(lst, i, ele)
  return lst
end

---@param val any
---@param n integer
function M.list_init(val, n)
  local list = {}
  local i = 1
  while i < n + 1 do
    list[i] = val
    i = i + 1
  end

  return list
end

---@param lst table
---@param val any
---@param cols integer[]?
function M.list_fill(lst, val, cols)
  if cols then
    for _, i in ipairs(cols) do
      lst[i] = val
    end
  end
end

---Clear/empty a list
---@generic T
---@param lst T[]
function M.list_clear(lst)
  -- for i = #lst, 1, -1 do
  --   lst[i] = nil
  -- end
  table_clear(lst)
  return lst
end

-- Clears / empyt a table
---@param tbl table
function M.table_clear(tbl)
  table_clear(tbl)
  return tbl
end

---@generic T
---@param tbl table
---@param key string
---@param val T
---@return T
function M.update_table(tbl, key, val)
  tbl[key] = val
  return val
end

---Reverse list like table, mutate list.
---@generic T
---@param lst T[]
---@return T[]
function M.list_reverse(lst)
  local mid = math.floor(#lst / 2)
  for i = 1, mid do
    lst[i], lst[#lst - i + 1] = lst[#lst - i + 1], lst[i]
  end
  return lst
end

---Returns true if any component in list is true
---@generic T
---@param fun fun(T): any
---@param lst T[]
---@return boolean
function M.list_any(fun, lst)
  for _, v in ipairs(lst) do
    if fun(v) then
      return true
    end
  end

  return false
end

---Returns true if all components in list are true
---@generic T
---@param fun fun(T): any
---@param lst T[]
---@return boolean
function M.list_all(fun, lst)
  for _, v in ipairs(lst) do
    if not fun(v) then
      return false
    end
  end

  return true
end

-- ===================
-- | Hunk list utils |
-- ===================

-- Gets hunk index and hunk offset given hunk offset list.
---@param offsets integer[]
---@param cursor_row integer
---@return integer hunk_index index of found hunk in list
---@return integer hunk_offset offset of found hunk
function M.get_hunk(offsets, cursor_row)
  if cursor_row < offsets[1] then
    return 1, offsets[1]
  end

  if #offsets > 4 then
    -- do binary search
    local start, stop = 1, #offsets
    local mid, hunk_offset

    while start < stop do
      mid = math.ceil((start + stop) / 2)
      hunk_offset = offsets[mid]
      if cursor_row == hunk_offset then
        return mid, hunk_offset
      elseif cursor_row < hunk_offset then
        stop = mid - 1
      else
        start = mid
      end
    end

    return stop, offsets[stop]
  end

  -- do linear search
  for i, hunk_offset in ipairs(offsets) do
    if cursor_row < hunk_offset then
      return i - 1, offsets[i - 1] or 1
    elseif cursor_row == hunk_offset then
      return i, hunk_offset
    end
  end

  return #offsets, offsets[#offsets]
end

M.BitArray = BitArray

return M
