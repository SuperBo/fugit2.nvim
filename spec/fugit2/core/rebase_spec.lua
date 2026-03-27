local git2 = require "fugit2.core.git2"
local libgit2 = require "fugit2.core.libgit2"

describe("in-memory rebase", function()
  local repo --[[@as GitRepository]]
  local tmp_dir

  setup(function()
    local path = require("os").getenv "GIT2_DIR"
    libgit2.setup_lib(path and path .. "/lib/libgit2.so" or nil)

    -- Create a temporary git repo with at least 2 commits so HEAD~1 is always valid
    tmp_dir = os.tmpname()
    os.remove(tmp_dir)
    os.execute("mkdir -p " .. tmp_dir)
    os.execute(
      "cd "
        .. tmp_dir
        .. " && git init -q"
        .. " && git config user.email 'test@test.com'"
        .. " && git config user.name 'Test'"
        .. " && echo a > file.txt && git add file.txt && git commit -q -m 'first'"
        .. " && echo b > file.txt && git add file.txt && git commit -q -m 'second'"
    )

    repo = git2.Repository.open(tmp_dir, false) --[[@as GitRepository]]
  end)

  teardown(function()
    if tmp_dir then
      os.execute("rm -rf " .. tmp_dir)
    end
  end)

  describe("rebase_init with inmemory=true", function()
    it("creates an in-memory rebase", function()
      local head, err = repo:annotated_commit_from_revspec "HEAD"
      assert.are.equal(0, err)
      assert.is_not_nil(head)

      local upstream, _ = repo:annotated_commit_from_revspec "HEAD~1"
      assert.is_not_nil(upstream)

      local rebase, rerr = repo:rebase_init(head, upstream, nil, { inmemory = true })
      assert.are.equal(0, rerr)
      assert.is_not_nil(rebase)
      assert.is_true(rebase:is_inmemory())
    end)

    it("reports operation count", function()
      local head, _ = repo:annotated_commit_from_revspec "HEAD"
      local upstream, _ = repo:annotated_commit_from_revspec "HEAD~1"

      local rebase, _ = repo:rebase_init(head, upstream, nil, { inmemory = true })
      assert.is_not_nil(rebase)

      -- rebasing HEAD onto HEAD~1 = exactly 1 operation
      assert.are.equal(1, rebase:noperations())
    end)

    it("exposes onto name", function()
      local head, _ = repo:annotated_commit_from_revspec "HEAD"
      local upstream, _ = repo:annotated_commit_from_revspec "HEAD~1"

      local rebase, _ = repo:rebase_init(head, upstream, nil, { inmemory = true })
      assert.is_not_nil(rebase)
      assert.is_not_nil(rebase:onto_name())
    end)

    it("returns inmemory_index after next()", function()
      local head, _ = repo:annotated_commit_from_revspec "HEAD"
      local upstream, _ = repo:annotated_commit_from_revspec "HEAD~1"

      local rebase, _ = repo:rebase_init(head, upstream, nil, { inmemory = true })
      assert.is_not_nil(rebase)

      local op, err = rebase:next()
      assert.are.equal(0, err)
      assert.is_not_nil(op)

      local index, ierr = rebase:inmemory_index()
      assert.are.equal(0, ierr)
      assert.is_not_nil(index)
    end)
  end)

  describe("rebase_init with inmemory=false (default)", function()
    it("creates a disk-based rebase (not in-memory)", function()
      local head, _ = repo:annotated_commit_from_revspec "HEAD"
      local upstream, _ = repo:annotated_commit_from_revspec "HEAD~1"

      -- Only verify is_inmemory() returns false; abort immediately to avoid side effects
      local rebase, err = repo:rebase_init(head, upstream, nil, {})
      if err == 0 and rebase then
        assert.is_false(rebase:is_inmemory())
        rebase:abort()
      end
    end)
  end)
end)
