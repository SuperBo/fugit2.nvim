local git2 = require "fugit2.core.git2"
local libgit2 = require "fugit2.core.libgit2"

describe("stash", function()
  local repo --[[@as GitRepository]]
  local tmp_dir

  setup(function()
    local path = require("os").getenv "GIT2_DIR"
    libgit2.setup_lib(path and path .. "/lib/libgit2.so" or nil)

    -- Create a temporary git repo with a committed file
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
    )

    repo = git2.Repository.open(tmp_dir, false) --[[@as GitRepository]]
  end)

  teardown(function()
    if tmp_dir then
      os.execute("rm -rf " .. tmp_dir)
    end
  end)

  describe("stash_list", function()
    it("returns empty list when no stashes exist", function()
      local entries, err = repo:stash_list()
      assert.are.equal(0, err)
      assert.are.same({}, entries)
    end)
  end)

  describe("stash_save", function()
    it("saves tracked changes with default message", function()
      -- Create a dirty working directory
      os.execute("cd " .. tmp_dir .. " && echo b > file.txt")

      local sig, sig_err = repo:signature_default()
      assert.are.equal(0, sig_err)
      assert.is_not_nil(sig)

      local oid, err = repo:stash_save(sig, nil, 0)
      assert.are.equal(0, err)
      assert.is_not_nil(oid)
    end)

    it("shows one stash after save", function()
      local entries, err = repo:stash_list()
      assert.are.equal(0, err)
      assert.are.equal(1, #entries)
      assert.are.equal(0, entries[1].index)
      assert.is_true(entries[1].message:len() > 0)
      assert.is_not_nil(entries[1].oid)
    end)

    it("saves with custom message", function()
      -- Create another dirty state
      os.execute("cd " .. tmp_dir .. " && echo c > file.txt")

      local sig, _ = repo:signature_default()
      local oid, err = repo:stash_save(sig, "my custom stash", 0)
      assert.are.equal(0, err)
      assert.is_not_nil(oid)
    end)

    it("saves with include untracked flag", function()
      -- Create an untracked file
      os.execute("cd " .. tmp_dir .. " && echo d > untracked.txt")

      local sig, _ = repo:signature_default()
      local oid, err = repo:stash_save(sig, "with untracked", git2.GIT_STASH.INCLUDE_UNTRACKED)
      assert.are.equal(0, err)
      assert.is_not_nil(oid)

      -- untracked file should be gone after stash
      local f = io.open(tmp_dir .. "/untracked.txt", "r")
      assert.is_nil(f)
    end)

    it("saves with keep index flag", function()
      -- Stage a change, then modify working dir further
      os.execute("cd " .. tmp_dir .. " && echo e > file.txt && git add file.txt && echo f > file.txt")

      local sig, _ = repo:signature_default()
      local oid, err = repo:stash_save(sig, "keep index", git2.GIT_STASH.KEEP_INDEX)
      assert.are.equal(0, err)
      assert.is_not_nil(oid)
    end)

    it("fails when there is nothing to stash", function()
      -- Reset to clean state
      os.execute("cd " .. tmp_dir .. " && git checkout -q -- . && git clean -fd -q")

      local sig, _ = repo:signature_default()
      local oid, err = repo:stash_save(sig, nil, 0)
      assert.is_nil(oid)
      assert.are.not_equal(0, err)
    end)
  end)

  describe("stash_list with multiple stashes", function()
    -- After the saves above, we should have multiple stashes
    it("lists stashes in correct order", function()
      local entries, err = repo:stash_list()
      assert.are.equal(0, err)
      assert.is_true(#entries >= 2)

      -- Stashes are ordered newest first (index 0 = most recent)
      for i, entry in ipairs(entries) do
        assert.are.equal(i - 1, entry.index)
        assert.is_true(entry.message:len() > 0)
        assert.is_not_nil(entry.oid)
      end
    end)

    it("preserves oid data after callback completes", function()
      local entries, _ = repo:stash_list()
      assert.is_true(#entries >= 1)

      -- Verify oid is a valid ObjectId with string representation
      local oid_str = entries[1].oid:tostring(8)
      assert.are.equal(8, oid_str:len())
      assert.is_true(oid_str:match "^[0-9a-f]+$" ~= nil)
    end)
  end)

  describe("stash_apply", function()
    it("applies a stash without removing it", function()
      -- Clean working dir first
      os.execute("cd " .. tmp_dir .. " && git checkout -q -- . && git clean -fd -q")

      local entries_before, _ = repo:stash_list()
      local count_before = #entries_before

      local err = repo:stash_apply(0)
      assert.are.equal(0, err)

      -- Stash should still be in the list
      local entries_after, _ = repo:stash_list()
      assert.are.equal(count_before, #entries_after)
    end)

    it("fails with invalid index", function()
      local err = repo:stash_apply(999)
      assert.are.not_equal(0, err)
    end)
  end)

  describe("stash_drop", function()
    it("drops a stash by index", function()
      local entries_before, _ = repo:stash_list()
      local count_before = #entries_before
      assert.is_true(count_before >= 1)

      local err = repo:stash_drop(0)
      assert.are.equal(0, err)

      local entries_after, _ = repo:stash_list()
      assert.are.equal(count_before - 1, #entries_after)
    end)

    it("renumbers indices after drop", function()
      -- Ensure we have at least 2 stashes
      os.execute("cd " .. tmp_dir .. " && git checkout -q -- . && git clean -fd -q")
      os.execute("cd " .. tmp_dir .. " && echo x > file.txt")
      local sig, _ = repo:signature_default()
      repo:stash_save(sig, "stash A", 0)
      os.execute("cd " .. tmp_dir .. " && echo y > file.txt")
      repo:stash_save(sig, "stash B", 0)

      local entries, _ = repo:stash_list()
      local count = #entries
      assert.is_true(count >= 2)

      -- stash@{0} should be "stash B" (newest)
      assert.is_true(entries[1].message:find("stash B") ~= nil)
      assert.are.equal(0, entries[1].index)
      assert.are.equal(1, entries[2].index)

      -- Drop stash@{0}
      repo:stash_drop(0)

      -- After drop, "stash A" should now be at index 0
      local entries_after, _ = repo:stash_list()
      assert.are.equal(count - 1, #entries_after)
      assert.are.equal(0, entries_after[1].index)
      assert.is_true(entries_after[1].message:find("stash A") ~= nil)
    end)

    it("fails with invalid index", function()
      local err = repo:stash_drop(999)
      assert.are.not_equal(0, err)
    end)
  end)

  describe("stash_pop", function()
    it("applies and removes a stash", function()
      -- Clean state and create a stash to pop
      os.execute("cd " .. tmp_dir .. " && git checkout -q -- . && git clean -fd -q")
      os.execute("cd " .. tmp_dir .. " && echo pop_test > file.txt")
      local sig, _ = repo:signature_default()
      repo:stash_save(sig, "to pop", 0)

      local entries_before, _ = repo:stash_list()
      local count_before = #entries_before
      assert.is_true(count_before >= 1)

      -- Clean working dir so pop can apply
      os.execute("cd " .. tmp_dir .. " && git checkout -q -- .")

      local err = repo:stash_pop(0)
      assert.are.equal(0, err)

      -- Stash should be removed
      local entries_after, _ = repo:stash_list()
      assert.are.equal(count_before - 1, #entries_after)

      -- Working dir should have the changes
      local f = io.open(tmp_dir .. "/file.txt", "r")
      assert.is_not_nil(f)
      local content = f:read "*a"
      f:close()
      assert.is_true(content:find "pop_test" ~= nil)
    end)

    it("fails with invalid index", function()
      local err = repo:stash_pop(999)
      assert.are.not_equal(0, err)
    end)
  end)
end)
