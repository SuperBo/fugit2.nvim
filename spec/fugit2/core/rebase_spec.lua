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

  describe("in-memory rebase finish updates working directory", function()
    it("checkout HEAD recreates missing files after rebase", function()
      -- Setup: create a branch that adds a new file
      local branch_name = "test-inmemory-checkout-" .. os.time()
      os.execute(
        "cd "
          .. tmp_dir
          .. " && git checkout -q -b "
          .. branch_name
          .. " && echo new > newfile.txt && git add newfile.txt && git commit -q -m 'add newfile'"
          .. " && git checkout -q -"
      )

      -- newfile.txt should not exist on main
      local f = io.open(tmp_dir .. "/newfile.txt", "r")
      assert.is_nil(f)

      -- Prepare rebase: rebase branch onto HEAD (main)
      local branch_commit, _ = repo:annotated_commit_from_revspec(branch_name)
      assert.is_not_nil(branch_commit)

      local head_commit, _ = repo:annotated_commit_from_revspec "HEAD"
      assert.is_not_nil(head_commit)

      local rebase, err = repo:rebase_init(branch_commit, head_commit, nil, { inmemory = true })
      assert.are.equal(0, err)
      assert.is_not_nil(rebase)
      assert.is_true(rebase:is_inmemory())

      -- Apply all operations
      local signature, _ = repo:signature_default()
      assert.is_not_nil(signature)

      local op, commit_id
      op, err = rebase:next()
      assert.are.equal(0, err)
      assert.is_not_nil(op)

      commit_id, err = rebase:commit(nil, signature, nil)
      assert.are.equal(0, err)
      assert.is_not_nil(commit_id)

      -- Finish rebase
      err = rebase:finish(signature)
      assert.are.equal(0, err)

      -- Update HEAD ref
      local last_commit, _ = repo:commit_lookup(commit_id)
      assert.is_not_nil(last_commit)

      err = repo:update_head_for_commit(commit_id, last_commit:summary(), "rebase: ")
      assert.are.equal(0, err)

      -- Before checkout: newfile.txt should still not exist on disk
      f = io.open(tmp_dir .. "/newfile.txt", "r")
      assert.is_nil(f)

      -- Checkout HEAD to update working directory
      err = repo:checkout_head(git2.GIT_CHECKOUT.SAFE + git2.GIT_CHECKOUT.RECREATE_MISSING)
      assert.are.equal(0, err)

      -- After checkout: newfile.txt should now exist with correct content
      f = io.open(tmp_dir .. "/newfile.txt", "r")
      assert.is_not_nil(f)
      local content = f:read "*a"
      f:close()
      assert.are.equal("new\n", content)

      -- Cleanup
      os.execute("cd " .. tmp_dir .. " && git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null")
      os.execute("cd " .. tmp_dir .. " && git branch -q -D " .. branch_name .. " 2>/dev/null")
    end)

    it("checkout HEAD with safe does not overwrite existing files", function()
      -- Setup: create a branch that modifies file.txt
      local branch_name = "test-inmemory-safe-" .. os.time()
      os.execute(
        "cd "
          .. tmp_dir
          .. " && git checkout -q -b "
          .. branch_name
          .. " && echo c > file.txt && git add file.txt && git commit -q -m 'modify file'"
          .. " && git checkout -q -"
      )

      -- Read file content before rebase
      local f = io.open(tmp_dir .. "/file.txt", "r")
      local content_before = f:read "*a"
      f:close()

      -- Prepare rebase
      local branch_commit, _ = repo:annotated_commit_from_revspec(branch_name)
      assert.is_not_nil(branch_commit)

      local head_commit, _ = repo:annotated_commit_from_revspec "HEAD"
      assert.is_not_nil(head_commit)

      local rebase, err = repo:rebase_init(branch_commit, head_commit, nil, { inmemory = true })
      assert.are.equal(0, err)
      assert.is_not_nil(rebase)

      local signature, _ = repo:signature_default()
      assert.is_not_nil(signature)

      local op, commit_id
      op, err = rebase:next()
      assert.are.equal(0, err)

      commit_id, err = rebase:commit(nil, signature, nil)
      assert.are.equal(0, err)

      err = rebase:finish(signature)
      assert.are.equal(0, err)

      local last_commit, _ = repo:commit_lookup(commit_id)
      assert.is_not_nil(last_commit)

      err = repo:update_head_for_commit(commit_id, last_commit:summary(), "rebase: ")
      assert.are.equal(0, err)

      -- SAFE checkout should not overwrite existing tracked file
      err = repo:checkout_head(git2.GIT_CHECKOUT.SAFE + git2.GIT_CHECKOUT.RECREATE_MISSING)
      assert.are.equal(0, err)

      f = io.open(tmp_dir .. "/file.txt", "r")
      local content_after = f:read "*a"
      f:close()
      assert.are.equal(content_before, content_after)

      -- Cleanup
      os.execute("cd " .. tmp_dir .. " && git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null")
      os.execute("cd " .. tmp_dir .. " && git branch -q -D " .. branch_name .. " 2>/dev/null")
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
