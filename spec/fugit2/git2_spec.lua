local git2 = require "fugit2.git2"
local libgit2 = require "fugit2.libgit2"

describe("git2", function()
  local repo --[[@as GitRepository]]
  local head --[[@as GitReference]]

  setup(function()
    local path = require("os").getenv "GIT2_DIR"
    libgit2.setup_lib(path and path .. "/lib/libgit2.so" or nil)

    repo = git2.Repository.open(".", false) --[[@as GitRepository]]
    head, _ = repo:head() --[[@as GitReference]]
  end)

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

    assert.are.equal(0, err)
    assert.is.not_nil(blame_opts)
    assert.are.equal(0, bit.band(blame_opts[0].flags, libgit2.GIT_BLAME.FIRST_PARENT))
    assert.are.not_equal(0, bit.band(blame_opts[0].flags, libgit2.GIT_BLAME.IGNORE_WHITESPACE))
    assert.are.equal(32, blame_opts[0].min_match_characters)
    assert.are.equal(oid, git2.ObjectId.borrow(blame_opts[0].oldest_commit))
    assert.are.equal(oid, git2.ObjectId.borrow(blame_opts[0].newest_commit))
  end)

  it("gets commit", function()
    local commit = head:peel_commit() --[[@as GitCommit]]
    assert.not_nil(head)

    local time = commit:time()

    assert.are.not_equal("", commit:summary())
    assert.are.not_equal("", commit:message())
    assert.is.not_nil(time.year)
    assert.is.not_nil(time.month)
    assert.is.not_nil(time.day)
    assert.is.not_nil(time.hour)
    assert.is_true(time.year >= 2023)
    assert.is_true(time.month >= 1)
    assert.is_true(time.month <= 12)
    assert.is_true(time.day >= 1)
    assert.is_true(time.day <= 31)
  end)
end)
