local git2 = require "fugit2.core.git2"
local libgit2 = require "fugit2.core.libgit2"

describe("cherry_pick", function()
  local repo --[[@as GitRepository]]
  local tmp_dir
  local pick_oid_str -- OID of the commit to cherry-pick
  local initial_head_oid_str

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

    -- Capture the initial HEAD OID on main
    local h2 = io.popen("cd " .. tmp_dir .. " && git rev-parse HEAD")
    if h2 then
      initial_head_oid_str = h2:read "*l"
      h2:close()
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

    it("creates a new commit without modifying the working directory", function()
      -- HEAD should have advanced to a new commit
      local handle = io.popen("cd " .. tmp_dir .. " && git rev-parse HEAD")
      local new_head_oid_str = handle and handle:read "*l" or nil
      if handle then
        handle:close()
      end
      assert.is_not_nil(new_head_oid_str)
      assert.are_not.equal(initial_head_oid_str, new_head_oid_str)

      -- Working directory must not contain new.txt (in-memory, not applied to workdir)
      local f = io.open(tmp_dir .. "/new.txt", "r")
      assert.is_nil(f, "new.txt must NOT exist in working directory for in-memory cherry-pick")
      if f then
        f:close()
      end
    end)

    it("new commit contains the cherry-picked file in its tree", function()
      -- The cherry-picked commit's tree should include new.txt
      local handle = io.popen("cd " .. tmp_dir .. " && git show HEAD:new.txt 2>/dev/null")
      local content = handle and handle:read "*a" or nil
      if handle then
        handle:close()
      end
      assert.is_not_nil(content)
      assert.is_true(content ~= nil and content:find "b" ~= nil)
    end)

    it("fails with an invalid OID", function()
      -- Manufacture an OID string that does not correspond to any object
      local bad_oid_str = ("0"):rep(40)
      local oid, oid_err = git2.ObjectId.from_string(bad_oid_str)
      assert.are.equal(0, oid_err)
      assert.is_not_nil(oid)

      local err = repo:cherry_pick(oid)
      assert.are_not.equal(0, err)
    end)
  end)
end)
