local utils = require "fugit2.utils"
local NuiTree = require "nui.tree"


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


describe("build_dir_tree/build_nui_tree_nodes", function()
  it("builds directory 1", function()
    local nodes = {
      { path = "a/a.txt", id = 1 },
      { path = "a/b.txt", id = 2 },
      { path = "c.txt",   id = 3 },
    }

    local tree = utils.build_dir_tree(function(n) return n.path end, nodes)

    assert(#vim.tbl_keys(tree), 2)
    assert.is_not_nil(tree["."])
    assert.is_not_nil(tree["a"])
    assert.is_not_nil(tree["a"]["."])
    assert.same({
      { path = "c.txt", id = 3 }
    }, tree["."])
    assert.same({
      { path = "a/a.txt", id = 1 },
      { path = "a/b.txt", id = 2 },
    }, tree["a"]["."])
  end)

  it("builds branch names", function()
    local nodes = {
      { name = "feature", id = 10, ar = "af" },
      { name = "feature/add-1", id = 11 },
      { name = "feature/project/add-project", id = 12 },
      { name = "feature/remove-2", id = 13 },
    }

    local tree = utils.build_dir_tree(function(val) return val.name end, nodes)

    assert(#vim.tbl_keys(tree), 2)
    assert.is_not_nil(tree["."])
    assert.is_not_nil(tree["feature"])
    assert.is_not_nil(tree["feature"]["."])
    assert.is_not_nil(tree["feature"]["project"])
    assert.is_not_nil(tree["feature"]["project"]["."])
    assert.same({ nodes[1] }, tree["."])
    assert.same({ nodes[2], nodes[4] }, tree["feature"]["."])
    assert.same({ nodes[3] }, tree["feature"]["project"]["."])
  end)

  it("builds NuiTree for branch names", function()
    local nodes = {
      { name = "feature", id = 10, ar = "af" },
      { name = "feature/add-1", id = 11 },
      { name = "feature/project/add-project", id = 12 },
      { name = "feature/remove-2", id = 13 },
    }
    local path_fn = function(v)
      return v.name
    end
    local node_fn = function(v)
      return NuiTree.Node({ id = v.id, text = vim.fs.basename(v.name) })
    end

    local dir_tree = utils.build_dir_tree(path_fn, nodes)
    local tree = utils.build_nui_tree_nodes(node_fn, dir_tree)

    assert.is_not_nil(tree)
    assert.equals(2, #tree)
    assert.equals("feature", tree[1].text)
    assert.equals("feature", tree[2].text)
    assert.equals(true, tree[1]:has_children())
    assert.equals(false, tree[2]:has_children())
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

  it("returns correct set indices", function()
    local bitarr = utils.BitArray.new()

    bitarr:append(false)
    bitarr:append(true)

    assert.same({2}, bitarr:get_set_indices())
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

  it("copy data", function()
    local b1 = utils.BitArray.new()
    b1:append(false)
    b1:append(true)
    local b2 = b1:copy():unset(2)

    assert.same({2}, b1:get_set_indices())
    assert.same({}, b2:get_set_indices())
  end)
end)


describe("list_utils", function()
  it("reverse list", function()
    local list = {1, 2, 4, 5}
    utils.list_reverse(list)

    assert.same({5, 4, 2, 1}, list)
  end)

  it("reverse list with odd length", function()
    local list = {4, 5, 6, 7, 8, 9, 10}
    utils.list_reverse(list)

    assert.same({ 10, 9, 8, 7, 6, 5 , 4 }, list)
  end)

  it("insert a sorted list", function()
    local list = { 3, 5 }

    utils.list_sorted_insert(list, 1)
    utils.list_sorted_insert(list, 4)
    utils.list_sorted_insert(list, 6)
    utils.list_sorted_insert(list, 2)

    assert.same({ 1, 2, 3, 4, 5, 6 }, list)
  end)
end)
