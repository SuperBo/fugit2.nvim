local context = require "plenary.context_manager"
local diff = require "fugit2.diff"


---@param path string
---@return string
local function read_patch_file(path)
  local ret = ""
  context.with(context.open(path, "r"), function(reader)
    ret = reader:read("*all")
  end)
  return ret
end

describe("parse_patch", function()
  local patch = read_patch_file("tests/resources/patch_a.diff")

  it("get correct header", function()
    local patch_item = diff.parse_patch(patch)

    assert.is_not_nil(patch_item.header)
    assert.array(patch_item.header).has.no.holes()
    assert.equals(4, #patch_item.header)
  end)

  it("get correct num hunk", function()
    local patch_item = diff.parse_patch(patch)

    assert.is_not_nil(patch_item.hunks)
    assert.array(patch_item.hunks).has.no.holes()
    assert.equals(4, #patch_item.hunks)
  end)

  it("get correct hunk", function()
    local patch_item = diff.parse_patch(patch)

    assert.is_not_nil(patch_item.hunks)
    assert.is_not_nil(patch_item.hunks[4])

    local hunk = patch_item.hunks[4]

    assert.equals("@@ -149,4 +172,23 @@ function PatchView:unmount()", hunk.header)
    assert.equals(" return PatchView", hunk.lines[#hunk.lines].text)
    assert.equals(" ", hunk.lines[#hunk.lines].c)
    assert.equals(92, hunk.lines[#hunk.lines].linenr)
    assert.equals(23, #hunk.lines)
  end)
end)
