
local git2 = require "fugit2.git2"

print "Welcome"
local test_repo = git2.Repository.open("/Users/superbo/Workspace/dagster-pipelines")
print(test_repo)
if test_repo then
  -- Branch
  print(test_repo)
  print(test_repo.path)
  local repo_head = git2.head(test_repo)
  if repo_head then
    print(repo_head)
    print("Is branch", repo_head.namespace == git2.GIT_REFERENCE_NAMESPACE.BRANCH)
    print("Branch name:", git2.Reference.shorthand(repo_head))

    -- Remote
    local remote_name, _ = test_repo:branch_remote_name("refs/remotes/origin/dev")
    print("Branch remote name:", remote_name)
  end



  -- Signature
  local sig, e = test_repo:signature_default()
  if sig then
    print("Signature Author:", sig:name())
  else
    print("Sig error: ", e)
  end

  -- Remote
  local remotes, _ = test_repo:remote_list()
  if remotes then
    for _, r in ipairs(remotes) do
      print(r)
    end
  end

  -- Status
  local repo_status, error = git2.status(test_repo)
  if repo_status then
    print("Status", #repo_status.status)
  else
    print("Status error", error)
  end


  local ref, _ = test_repo:reference_lookup("refs/remotes/origin/HEAD")
  if ref then
    print("Refname: ", ref.name, ref.namespace)
    local target = ref:symbolic_target()
    print(target)
  end

  -- Config
  local config, _ = test_repo:config()
  if config then
    -- local entries, err = config:entries()
    -- if err == 0 and entries then
    --   print(#entries)
    --   for i, en in ipairs(entries) do
    --     print(i, en.name, en.value)
    --   end
    -- end
    local remote, _ = config:get_string("branch.main.remote")
    local push_remote, _ = config:get_string("branch.main.pushremote")
    print(remote, push_remote)
  end

end
