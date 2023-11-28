local utils = require "fugit2.utils"


describe("make_relative_path", function()
  it("returns same path", function()
    assert.equals(".", utils.make_relative_path("a/b/d", "a/b/d"))
  end)

  it("returns same directory", function()
    assert.equals("c.txt", utils.make_relative_path("a/b", "a/b/c.txt"))
  end)

  it("returns file in parent dir", function()
    assert.equals("../c.txt", utils.make_relative_path("a/b", "a/c.txt"))
  end)

  it("return file parent dir same name", function()
    assert.equals("../fugit2.lua", utils.make_relative_path("lua/fugit2", "lua/fugit2.lua"))
  end)

  it("returns file in two parent dir", function()
    assert.equals("../../f.txt", utils.make_relative_path("a/b/c", "a/f.txt"))
  end)

  it("returns file in three parent dir", function()
    assert.equals("../../../f.txt", utils.make_relative_path("a/b/c/d", "a/f.txt"))
  end)

  it("returns child dir", function()
    assert.equals("c/f.txt", utils.make_relative_path("a/a", "a/a/c/f.txt"))
  end)

end)


describe("bitarray", function()
  it("returns empty unset indices for empty bitmap", function()
    local bitarr = utils.BitArray.new()
    local unset = bitarr:get_unset_indices()

    assert.equals(0, #unset)
    assert.equals(0, bitarr.buf)
    assert.equals(0, bitarr.n)
  end)

  it("can push and pop", function()
    local bitarr = utils.BitArray.new()
    local pop_1 = bitarr:pop()
    bitarr:append(true)
    bitarr:append(false)
    bitarr:append(true)
    local pop_2 = bitarr:pop()
    bitarr:append(false)
    local pop_3 = bitarr:pop()
    local pop_4 = bitarr:pop()
    local pop_5 = bitarr:pop()

    assert.is_nil(pop_1)
    assert.is_true(pop_2)
    assert.is_false(pop_3)
    assert.is_false(pop_4)
    assert.is_true(pop_5)
  end)

  it("returns correct unset indices", function()
    local bitarr = utils.BitArray.new()

    bitarr:append(false)
    local unset_1 = bitarr:get_unset_indices()

    bitarr:append(true)
    local unset_2 = bitarr:get_unset_indices()

    bitarr:append(true)
    local unset_3 = bitarr:get_unset_indices()

    bitarr:append(false)
    local unset_4 = bitarr:get_unset_indices()

    bitarr:append(true)
    local unset_5 = bitarr:get_unset_indices()

    assert.same({1}, unset_1)
    assert.same({1}, unset_2)
    assert.same({1}, unset_3)
    assert.same({1, 4}, unset_4)
    assert.same({1, 4}, unset_5)
  end)

  it("sets unset indices correctly", function()
    local bitarr = utils.BitArray.new()

    bitarr:append(false)
    local unset_1 = bitarr:set_unset_indices()

    bitarr:append(true)
    local unset_2 = bitarr:set_unset_indices()

    bitarr:append(true)
    local unset_3 = bitarr:set_unset_indices()

    bitarr:append(false)
    local unset_4 = bitarr:set_unset_indices()

    assert.same({1}, unset_1)
    assert.same({}, unset_2)
    assert.same({}, unset_3)
    assert.same({4}, unset_4)
  end)

  it("sets k unset indices correctly", function()
    local bitarr = utils.BitArray.new()
    bitarr:append(true)
    bitarr:append(false)
    bitarr:append(false)
    bitarr:append(true)

    local unset_1 = bitarr:set_k_unset_indices(1)

    bitarr:append(false)
    local unset_2 = bitarr:set_k_unset_indices(4)
    local unset_3 = bitarr:get_unset_indices()

    assert.equals(7, bitarr.n)
    assert.equals(127, bitarr.buf)
    assert.same({2}, unset_1)
    assert.same({3, 5, 6, 7}, unset_2)
    assert.same({}, unset_3)
  end)
end)
