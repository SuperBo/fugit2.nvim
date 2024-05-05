local M = {}

local S_IFMT = 0xf000
local S_IFSOCK = 0xc000
local S_IFLNK = 0xa000
local S_IFREG = 0x8000
local S_IFBLK = 0x6000
local S_IFDIR = 0x4000
local S_IFCHR = 0x2000
local S_IFIFO = 0x1000
local S_ISUID = 0x800
local S_ISGID = 0x400
local S_ISVTX = 0x200

M.S_IFMT = S_IFMT
M.S_IFLNK = S_IFLNK
M.S_IFREG = S_IFREG
M.S_IFDIR = S_IFDIR

---@param m integer file mode
---@return boolean
function M.S_ISLNK(m)
  return bit.band(m, S_IFMT) == S_IFLNK
end

---@param m integer file mode
---@return boolean
function M.S_ISREG(m)
  return bit.band(m, S_IFMT) == S_IFREG
end

---@param m integer file mode
---@return boolean
function M.S_ISDIR(m)
  return bit.band(m, S_IFMT) == S_IFDIR
end

---@param m integer file mode
---@return boolean
function M.S_ISCHR(m)
  return bit.band(m, S_IFMT) == S_IFCHR
end

---@param m integer file mode
---@return boolean
function M.S_ISBLK(m)
  return bit.band(m, S_IFMT) == S_IFBLK
end

---@param m integer file mode
---@return boolean
function M.S_ISFIFO(m)
  return bit.band(m, S_IFMT) == S_IFIFO
end

---@param m integer file mode
---@return boolean
function M.S_ISSOCK(m)
  return bit.band(m, S_IFMT) == S_IFSOCK
end

return M
