local NuiTree = require "nui.tree"
local utils = require "fugit2.utils"

describe("make_relative_path", function()
  it("returns same path", function()
    assert.are.equal(".", utils.make_relative_path("a/b/d", "a/b/d"))
  end)

  it("returns same directory", function()
    assert.are.equal("c.txt", utils.make_relative_path("a/b", "a/b/c.txt"))
  end)

  it("returns file in parent dir", function()
    assert.are.equal("../c.txt", utils.make_relative_path("a/b", "a/c.txt"))
  end)

  it("return file parent dir same name", function()
    assert.are.equal("../fugit2.lua", utils.make_relative_path("lua/fugit2", "lua/fugit2.lua"))
  end)

  it("returns file in two parent dir", function()
    assert.are.equal("../../f.txt", utils.make_relative_path("a/b/c", "a/f.txt"))
  end)

  it("returns file in three parent dir", function()
    assert.are.equal("../../../f.txt", utils.make_relative_path("a/b/c/d", "a/f.txt"))
  end)

  it("returns child dir", function()
    assert.are.equal("c/f.txt", utils.make_relative_path("a/a", "a/a/c/f.txt"))
  end)
end)

describe("build_dir_tree/build_nui_tree_nodes", function()
  it("builds directory 1", function()
    local nodes = {
      { path = "a/a.txt", id = 1 },
      { path = "a/b.txt", id = 2 },
      { path = "c.txt", id = 3 },
    }

    local tree = utils.build_dir_tree(function(n)
      return n.path
    end, nodes)

    assert(#vim.tbl_keys(tree), 2)
    assert.is.not_nil(tree.files)
    assert.is.not_nil(tree.children)
    assert.is.not_nil(tree.children["a"])
    assert.is.not_nil(tree.children["a"].files)
    assert.same({
      { path = "c.txt", id = 3 },
    }, tree.files)
    assert.same({
      { path = "a/a.txt", id = 1 },
      { path = "a/b.txt", id = 2 },
    }, tree.children["a"].files)
  end)

  it("builds branch names", function()
    local nodes = {
      { name = "feature", id = 10, ar = "af" },
      { name = "feature/add-1", id = 11 },
      { name = "feature/project/add-project", id = 12 },
      { name = "feature/remove-2", id = 13 },
    }

    local tree = utils.build_dir_tree(function(val)
      return val.name
    end, nodes)

    assert(#vim.tbl_keys(tree), 2)
    assert.is.not_nil(tree.files)
    assert.is.not_nil(tree.children["feature"])
    assert.is.not_nil(tree.children["feature"].files)
    assert.is.not_nil(tree.children["feature"].children["project"])
    assert.is.not_nil(tree.children["feature"].children["project"].files)
    assert.are.same({ nodes[1] }, tree.files)
    assert.are.same({ nodes[2], nodes[4] }, tree.children["feature"].files)
    assert.are.same({ nodes[3] }, tree.children["feature"].children["project"].files)
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
      return NuiTree.Node { id = v.id, text = vim.fs.basename(v.name) }
    end

    local dir_tree = utils.build_dir_tree(path_fn, nodes)
    local tree = utils.build_nui_tree_nodes(node_fn, dir_tree)

    assert.is.not_nil(tree)
    assert.are.equal(2, #tree)
    assert.are.equal("feature", tree[1].text)
    assert.are.equal("feature", tree[2].text)
    assert.are.equal(true, tree[1]:has_children())
    assert.are.equal(false, tree[2]:has_children())
  end)

  it("compress dir tree simple", function()
    local dir_tree = {
      children = {
        a = {
          children = {
            b = {
              children = {
                c = { files = { "file1", "file2" } },
              },
            },
          },
        },
      },
    }

    local compressed = utils.compress_dir_tree(dir_tree)

    assert.is.not_nil(compressed.children)
    assert.is_nil(compressed.children["a"])
    assert.is_nil(compressed.children["b"])
    assert.is_nil(compressed.children["c"])
    assert.is.not_nil(compressed.children["a/b/c"])
    assert.are.same({ files = { "file1", "file2" } }, compressed.children["a/b/c"])
  end)

  it("compress dir tree complex", function()
    local nodes = {
      { path = "a/a.txt", id = 1 },
      { path = "a/b.txt", id = 2 },
      { path = "c.txt", id = 3 },
      { path = "d/e/g/h/file1.txt", id = 4 },
      { path = "d/e/g/h/file2.txt", id = 5 },
    }

    local tree = utils.build_dir_tree(function(n)
      return n.path
    end, nodes)
    local compressed = utils.compress_dir_tree(tree)

    assert.is.not_nil(compressed.children)
    assert.same({ nodes[3] }, tree.files)
    assert.is_nil(compressed.children["d"])
    assert.are.same({ files = { nodes[1], nodes[2] } }, compressed.children["a"])
    assert.are.same({ files = { nodes[4], nodes[5] } }, compressed.children["d/e/g/h"])
  end)
end)

describe("bitarray", function()
  it("returns empty unset indices for empty bitmap", function()
    local bitarr = utils.BitArray.new()
    local unset = bitarr:get_unset_indices()

    assert.are.equal(0, #unset)
    assert.are.equal(0, bitarr.buf)
    assert.are.equal(0, bitarr.n)
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

  it("sets four indices correctly", function()
    local b = utils.BitArray.new()
    b:append(false)
    b:append(false)
    b:append(false)
    b:append(false)

    assert.equals(4, b.n)

    b:set(1)
    b:set(4)

    assert.equals(9, b.buf)
  end)

  it("unsets two indices correctly", function()
    local b = utils.BitArray.new()
    b:set_k_unset_indices(2)
    assert.are.equal(3, b.buf)

    b:unset(2)

    assert.are.equal(2, b.n)
    assert.are.equal(2, b.buf)
    assert.are.same({ 1 }, b:get_set_indices())
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

    assert.are.same({ 1 }, unset_1)
    assert.are.same({ 1 }, unset_2)
    assert.are.same({ 1 }, unset_3)
    assert.are.same({ 1, 4 }, unset_4)
    assert.are.same({ 1, 4 }, unset_5)
  end)

  it("returns correct set indices", function()
    local bitarr = utils.BitArray.new()

    bitarr:append(false)
    bitarr:append(true)

    assert.are.same({ 2 }, bitarr:get_set_indices())
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

    assert.are.same({ 1 }, unset_1)
    assert.are.same({}, unset_2)
    assert.are.same({}, unset_3)
    assert.are.same({ 4 }, unset_4)
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

    assert.are.equal(7, bitarr.n)
    assert.are.equal(127, bitarr.buf)
    assert.are.same({ 2 }, unset_1)
    assert.are.same({ 3, 5, 6, 7 }, unset_2)
    assert.are.same({}, unset_3)
  end)

  it("copy data", function()
    local b1 = utils.BitArray.new()
    b1:append(false)
    b1:append(true)
    local b2 = b1:copy():unset(2)

    assert.are.same({ 2 }, b1:get_set_indices())
    assert.are.same({}, b2:get_set_indices())
  end)
end)

describe("list_utils", function()
  it("reverse list", function()
    local list = { 1, 2, 4, 5 }
    utils.list_reverse(list)

    assert.are.same({ 5, 4, 2, 1 }, list)
  end)

  it("reverse list with odd length", function()
    local list = { 4, 5, 6, 7, 8, 9, 10 }
    utils.list_reverse(list)

    assert.are.same({ 10, 9, 8, 7, 6, 5, 4 }, list)
  end)

  it("insert a sorted list", function()
    local list = { 3, 5 }

    utils.list_sorted_insert(list, 1)
    utils.list_sorted_insert(list, 4)
    utils.list_sorted_insert(list, 6)
    utils.list_sorted_insert(list, 2)

    assert.are.same({ 1, 2, 3, 4, 5, 6 }, list)
  end)
end)

describe("get_hunk", function()
  it("returns first hunk when negative index", function()
    local offsets = { 10, 18, 19, 20 }
    local offsets2 = { 10, 18, 19, 20, 28, 30, 32 }

    local i1, o1 = utils.get_hunk(offsets, 5)
    local i2, o2 = utils.get_hunk(offsets, -1)
    local i3, o3 = utils.get_hunk(offsets2, 8)

    assert.are.equal(i1, 1)
    assert.are.equal(10, o1)
    assert.are.equal(i2, 1)
    assert.are.equal(10, o2)
    assert.are.equal(i3, 1)
    assert.are.equal(10, o3)
  end)

  it("returns last hunk when out of last offset", function()
    local offsets1 = { 2, 6, 9, 10 }
    local offsets2 = { 1, 6, 9, 10, 12, 16 }

    local i1, o1 = utils.get_hunk(offsets1, 15)
    local i2, o2 = utils.get_hunk(offsets2, 20)

    assert.are.equal(#offsets1, i1)
    assert.are.equal(offsets1[#offsets1], o1)
    assert.are.equal(#offsets2, i2)
    assert.are.equal(offsets2[#offsets2], o2)
  end)

  it("returns correct hunk for small array", function()
    local offsets = { 2, 6, 9, 10 }

    local i1, off1 = utils.get_hunk(offsets, 2)
    local i2, off2 = utils.get_hunk(offsets, 8)
    local i3, off3 = utils.get_hunk(offsets, 9)
    local i4, off4 = utils.get_hunk(offsets, 12)

    assert.are.equal(1, i1)
    assert.are.equal(2, off1)
    assert.are.equal(2, i2)
    assert.are.equal(6, off2)
    assert.are.equal(3, i3)
    assert.are.equal(9, off3)
    assert.are.equal(4, i4)
    assert.are.equal(10, off4)
  end)

  it("returns correct hunk for big array", function()
    local offsets = { 2, 6, 10, 14, 18, 22, 26, 30, 34, 38 }

    local expected_ids = { 1 }
    local expected_offs = { 2 }
    for i, off in ipairs(offsets) do
      expected_ids[#expected_ids + 1] = i
      expected_ids[#expected_ids + 1] = i
      expected_offs[#expected_offs + 1] = off
      expected_offs[#expected_offs + 1] = off
    end

    local indices, offs = {}, {}
    for i = 0, 40, 2 do
      local j, off = utils.get_hunk(offsets, i)
      indices[#indices + 1] = j
      offs[#offs + 1] = off
    end

    assert.are.same(expected_ids, indices)
    assert.are.same(expected_offs, offs)
  end)
end)
