-- Test git blame parse module

local blame = require "fugit2.core.blame"
local context = require "plenary.context_manager"

local RESOURCE_DIR = "spec/resources/"

---@param path string
---@return string
local function read_blame_file(path)
  local result = context.with(context.open(RESOURCE_DIR .. path), function(reader)
    return reader:read "*all"
  end)
  return result
end

describe("git_blame", function()
  it("parses git blame output", function()
    local stdout = read_blame_file "blame_a.txt"

    local hunks = blame.parse_git_blame_porcelain(stdout)

    assert.array(hunks).has.no.holes(6)
    assert.are.equal(6, #hunks)
    assert.are.equal(1, hunks[1].num_lines)
    assert.are.equal(2, hunks[4].num_lines)
    assert.are.equal(1, hunks[1].start_linenr)
    assert.are.equal(2, hunks[2].start_linenr)
    assert.are.equal(3, hunks[3].start_linenr)
    assert.are.equal(4, hunks[4].start_linenr)
    assert.are.equal(6, hunks[5].start_linenr)
    assert.are.equal("Scott Chacon", hunks[1].author_name)
    assert.are.equal("Vicent Martí", hunks[1].committer_name)
    assert.are.equal("Haneef Mubarak", hunks[2].author_name)
  end)

  it("parses git blame with uncommitted changes", function()
    local stdout = read_blame_file "blame_b.txt"

    local hunks = blame.parse_git_blame_porcelain(stdout)

    assert.array(hunks).has.no.holes(10)
    assert.are.equal(10, #hunks)
    assert.are.equal(3, hunks[10].num_lines)
    assert.are.equal(11, hunks[10].start_linenr)
    assert.are.equal(11, hunks[10].orig_start_linenr)
    assert.are.equal("You", hunks[10].author_name)
    assert.are.equal("Uncommitted changes", hunks[10].message)
    assert.is_nil(hunks[10].date)
  end)
end)
