-- Module contains dynamic growing array implementation

local ffi = require "ffi"

-- Dynami resizing array
---@class Fugit2DynamicArray
---@field size integer
---@field capacity integer
---@field grow_size integer
---@field data ffi.cdata*
---@field _data_ctype ffi.ctype*
local Array = {}
function Array:__index(key)
  if type(key) == "number" then
    return self.data[key - 1]
  end

  return Array[key]
end

---@param init_capacity integer
---@param grow_size integer
---@param data_ctype ffi.ctype*
---@return Fugit2DynamicArray
function Array.new(init_capacity, grow_size, data_ctype)
  assert(init_capacity > 0)
  assert(grow_size > 0)
  local arr = {
    size = 0,
    capacity = init_capacity,
    grow_size = grow_size,
    data = data_ctype(init_capacity),
    _data_ctype = data_ctype,
  }
  setmetatable(arr, Array)

  return arr
end

function Array:__newindex(index, value)
  if type(index) == "number" then
    self.data[index - 1] = value
  end
end

---@return number index
function Array:append()
  if self.size == self.capacity then
    -- increase array
    self.capacity = self.size + self.grow_size
    local new_data = self._data_ctype(self.capacity)
    local num_bytes = ffi.sizeof(self._data_ctype, self.size)
    if num_bytes then
      ffi.copy(new_data, self.data, num_bytes)
    end

    self.data = new_data
  end

  self.size = self.size + 1
  -- return self.data, idx
  return self.size
end

---@param index number 1-based index
function Array:get(index)
  return self.data[index - 1]
end

return Array
