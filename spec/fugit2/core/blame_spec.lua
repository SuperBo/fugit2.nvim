-- Test git blame parse module

local blame = require "fugit2.core.blame"
local context = require "plenary.context_manager"

local RESOURCE_DIR = "tests/resources/"

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

    assert.array(hunks).has.no.holes()
    assert.equals(6, #hunks)
    assert.equals(1, hunks[1].num_lines)
    assert.equals(2, hunks[4].num_lines)
    assert.equals(1, hunks[1].start_linenr)
    assert.equals(2, hunks[2].start_linenr)
    assert.equals(3, hunks[3].start_linenr)
    assert.equals(4, hunks[4].start_linenr)
    assert.equals(6, hunks[5].start_linenr)
    assert.equals("Scott Chacon", hunks[1].author_name)
    assert.equals("Vicent Martí", hunks[1].committer_name)
    assert.equals("Haneef Mubarak", hunks[2].author_name)
  end)

  it("parses git blame with uncommitted changes", function()
    local stdout = read_blame_file "blame_b.txt"

    local hunks = blame.parse_git_blame_porcelain(stdout)

    assert.array(hunks).has.no.holes()
    assert.equals(10, #hunks)
    assert.equals(3, hunks[10].num_lines)
    assert.equals(11, hunks[10].start_linenr)
    assert.equals(11, hunks[10].orig_start_linenr)
    assert.equals("You", hunks[10].author_name)
    assert.equals("Uncommitted changes", hunks[10].message)
    assert.is_nil(hunks[10].date)
  end)
end)
