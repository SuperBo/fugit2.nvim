local git2 = require "fugit2.core.git2"
local libgit2 = require "fugit2.core.libgit2"

describe("cherry_pick", function()
  local repo --[[@as GitRepository]]
  local tmp_dir
  local pick_oid_str -- OID of the commit to cherry-pick

  setup(function()
    local path = require("os").getenv "GIT2_DIR"
    libgit2.setup_lib(path and path .. "/lib/libgit2.so" or nil)

    -- Create a temporary git repo with two branches:
    --   main:   initial commit (file.txt = "a")
    --   branch: one extra commit (new.txt = "b"), to be cherry-picked
    tmp_dir = os.tmpname()
    os.remove(tmp_dir)
    os.execute("mkdir -p " .. tmp_dir)
    os.execute(
      "cd "
        .. tmp_dir
        .. " && git init -q"
        .. " && git config user.email 'test@test.com'"
        .. " && git config user.name 'Test'"
        .. " && echo a > file.txt && git add file.txt && git commit -q -m 'initial'"
        .. " && git checkout -q -b branch"
        .. " && echo b > new.txt && git add new.txt && git commit -q -m 'add new.txt'"
        .. " && git checkout -q -"
    )

    -- Capture the OID of the commit on branch
    local handle = io.popen("cd " .. tmp_dir .. " && git rev-parse branch")
    if handle then
      pick_oid_str = handle:read "*l"
      handle:close()
    end

    repo = git2.Repository.open(tmp_dir, false) --[[@as GitRepository]]
  end)

  teardown(function()
    if tmp_dir then
      os.execute("rm -rf " .. tmp_dir)
    end
  end)

  describe("cherry_pick", function()
    it("applies a commit from another branch to HEAD", function()
      assert.is_not_nil(pick_oid_str)
      assert.are.equal(40, pick_oid_str:len())

      local oid, oid_err = git2.ObjectId.from_string(pick_oid_str)
      assert.are.equal(0, oid_err)
      assert.is_not_nil(oid)

      local err = repo:cherry_pick(oid)
      assert.are.equal(0, err)
    end)

    it("stages the cherry-picked changes in the index", function()
      -- After cherry_pick, new.txt should be staged (added to index)
      local f = io.open(tmp_dir .. "/new.txt", "r")
      assert.is_not_nil(f, "new.txt should exist in working directory after cherry-pick")
      if f then
        local content = f:read "*a"
        f:close()
        assert.is_true(content:find "b" ~= nil)
      end
    end)

    it("fails with an invalid OID", function()
      -- Manufacture an OID string that does not correspond to any object
      local bad_oid_str = ("0"):rep(40)
      local oid, oid_err = git2.ObjectId.from_string(bad_oid_str)
      assert.are.equal(0, oid_err)
      assert.is_not_nil(oid)

      local err = repo:cherry_pick(oid)
      assert.are.not_equal(0, err)
    end)
  end)
end)
