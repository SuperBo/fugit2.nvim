local git2 = require "fugit2.git2"
local libgit2 = require "fugit2.libgit2"

libgit2.load_library()

describe("git2", function()
  local repo = git2.Repository.open(".", false) --[[@as GitRepository]]
  local head, _ = repo:head() --[[@as GitReference]]

  it("inits blame_options correctly", function()
    local oid, _ = head:target() --[[@as GitObjectId]]
    assert.not_nil(oid)

    ---@type GitBlameOptions
    local opts = {
      ignore_whitespace = true,
      min_match_characters = 32,
      oldest_commit = oid,
      newest_commit = oid,
    }

    local blame_opts, err = git2.init_blame_options(opts)

    assert.equals(0, err)
    assert.not_nil(blame_opts)
    assert.equals(0, bit.band(blame_opts[0].flags, libgit2.GIT_BLAME.FIRST_PARENT))
    assert.not_equals(0, bit.band(blame_opts[0].flags, libgit2.GIT_BLAME.IGNORE_WHITESPACE))
    assert.equals(32, blame_opts[0].min_match_characters)
    assert.equals(oid, git2.ObjectId.borrow(blame_opts[0].oldest_commit))
    assert.equals(oid, git2.ObjectId.borrow(blame_opts[0].newest_commit))
  end)

  it("gets commit", function()
    local commit = head:peel_commit() --[[@as GitCommit]]
    assert.not_nil(head)

    local time = commit:time()

    assert.not_equals("", commit:summary())
    assert.not_equals("", commit:message())
    assert.not_nil(time.year)
    assert.not_nil(time.month)
    assert.not_nil(time.day)
    assert.not_nil(time.hour)
    assert(time.year >= 2023)
    assert(time.month >= 1)
    assert(time.month <= 12)
    assert(time.day >= 1)
    assert(time.day <= 31)
  end)
end)
