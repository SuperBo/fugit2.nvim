local ffi = require "ffi"

---@class Fugit2Matrix
---@field matrix ffi.cdata*
---@field n integer num col
local Matrix = {}
Matrix.__index = Matrix

---@param m integer num row
---@param n integer num col
---@return Fugit2Matrix
function Matrix.new_int8(m, n)
  local mat = { matrix = ffi.new("uint8_t[?]", m * n), n = n }
  setmetatable(mat, Matrix)
  return mat
end

---@param m integer num row
---@param n integer num col
---@return Fugit2Matrix
function Matrix.new_int16(m, n)
  local mat = { matrix = ffi.new("int16_t[?]", m * n), n = n }
  setmetatable(mat, Matrix)
  return mat
end

---@param i integer
---@param j integer
---@return number?
function Matrix:at(i, j)
  return tonumber(self.matrix[i * self.n + j])
end

return Matrix
