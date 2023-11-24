local utils = require "fugit2.utils"

-- describe("setup", function()
--   it("works with default", function()
--     assert("my first function with param = Hello!", plugin.hello())
--   end)
--
--   it("works with custom var", function()
--     plugin.setup({ opt = "custom" })
--     assert("my first function with param = custom", plugin.hello())
--   end)
-- end)

describe("make_relative_path", function ()
  it("returns same path", function ()
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

  it("return child dir", function()
    assert.equals("c/f.txt", utils.make_relative_path("a/a", "a/a/c/f.txt"))
  end)

end)
