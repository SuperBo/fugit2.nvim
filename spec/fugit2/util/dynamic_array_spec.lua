-- Test dynamic array module

local DynamicArray = require "fugit2.util.dynamic_array"
local ffi = require "ffi"
local libgit2 = require "fugit2.core.libgit2"

describe("DynamicArray", function()
  it("init array", function()
    local arr = DynamicArray.new(4, 4, ffi.typeof "git_rebase_operation[?]")

    assert.not_nil(arr)
    assert.are.equal(0, arr.size)
    assert.are.equal(4, arr.capacity)
  end)

  it("append element", function()
    local arr = DynamicArray.new(4, 4, ffi.typeof "size_t[?]")

    local i = arr:append()
    arr[i] = 12LL

    assert.not_nil(arr)
    assert.are.equal(1, arr.size)
    assert.are.equal(4, arr.capacity)
    assert.are.equal(1, i)
    assert.are.equal(12, arr[1])
    assert.are.not_equal(0, arr[1])
  end)

  it("grow array", function()
    local arr = DynamicArray.new(4, 4, ffi.typeof "size_t[?]")
    for i = 1, 6 do
      local j = arr:append()
      arr[j] = i
    end

    assert.no_nil(arr)
    assert.are.equal(6, arr.size)
    assert.are.equal(8, arr.capacity)
    for i = 1, 6 do
      assert.are.equal(i, arr[i])
    end
  end)
end)
