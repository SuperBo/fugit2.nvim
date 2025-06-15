---Module contains reimplementation of git rebase
---Extends libgit2 git rebase with support for
---SQUASH AND FIXUP

local DynamicArray = require "fugit2.util.dynamic_array"
local git2 = require "fugit2.git2"
local libgit2 = require "fugit2.libgit2"

---@module "fugit2.core.git_rebase"
local M = {}

---@enum FUGIT2_GIT_REBASE_OPERATION
M.GIT_REBASE_OPERATION = {
  PICK = 0,
  REWORD = 1,
  EDIT = 2,
  SQUASH = 3,
  FIXUP = 4,
  EXEC = 5,
  DROP = 6,
  BREAK = 7,
  BASE = 8,
}

-- =================================
-- | Rewrite libgit2 rebase in lua |
-- =================================

-- Fugit2 Git In-memory rebase. DEPRECATED
---@class Fugit2GitRebase
---@field repo GitRepository
---@field last_commit GitCommit Last commit
---@field operations Fugit2DynamicArray
---@field onto_id GitObjectId
---@field onto_name string
local GitRebase = {}
GitRebase.__index = GitRebase

---@param repo ffi.cdata* git_repository pointer
---@param branch ffi.cdata*? git_annotated_commit pointer
---@param upstream ffi.cdata*? git_annotated_commit pointer
---@param onto ffi.cdata*? git_annotated_commit pointer
---@return Fugit2DynamicArray?
---@return GIT_ERROR
local function rebase_init_operations(repo, branch, upstream, onto)
  local revwalk = libgit2.git_revwalk_double_pointer(0LL)
  local commit = libgit2.git_commit_double_pointer(0LL)
  local merge = false
  local id = libgit2.git_oid()
  local operations, err

  if not upstream then
    upstream = onto
  end

  err = libgit2.C.git_revwalk_new(revwalk, repo)
  if err ~= 0 then
    return nil, err
  end

  err = libgit2.C.git_revwalk_push(revwalk[0], libgit2.C.git_annotated_commit_id(branch))
  if err ~= 0 then
    libgit2.C.git_revwalk_free(revwalk[0])
    return nil, err
  end

  err = libgit2.C.git_revwalk_hide(revwalk[0], libgit2.C.git_annotated_commit_id(upstream))
  if err ~= 0 then
    libgit2.C.git_revwalk_free(revwalk[0])
    return nil, err
  end

  libgit2.C.git_revwalk_sorting(revwalk[0], libgit2.GIT_SORT.REVERSE)

  local init_operation = M.GIT_REBASE_OPERATION.PICK
  operations = DynamicArray.new(16, 16, libgit2.git_rebase_operation_array)
  while true do
    err = libgit2.C.git_revwalk_next(id, revwalk[0])
    if err ~= 0 then
      break
    end

    err = libgit2.C.git_commit_lookup(commit, repo, id)
    if err ~= 0 then
      goto rebase_init_operations_cleanup
    end

    merge = (libgit2.C.git_commit_parentcount(commit[0]) > 1)
    libgit2.C.git_commit_free(commit[0])

    if not merge then
      local position = operations:append()
      local op = operations[position]
      op["type"] = init_operation
      libgit2.C.git_oid_cpy(op["id"], id)
      op["exec"] = 0LL
    end
  end

  err = 0

  ::rebase_init_operations_cleanup::
  libgit2.C.git_revwalk_free(revwalk[0])
  return operations, err
end

---@param repo GitRepository git_repository pointer
---@param onto GitAnnotatedCommit git_annotated_commit pointer
---@param operations Fugit2DynamicArray
---@return Fugit2GitRebase?
---@return GIT_ERROR
local function rebase_init_inmemory(repo, onto, operations)
  local last_commit = libgit2.git_commit_double_pointer()
  local err = libgit2.C.git_commit_lookup(repo.repo, libgit2.C.git_annotated_commit_id(onto.commit))
  if err ~= 0 then
    return nil, err
  end

  local onto_id = onto:id()

  local onto_ref = onto:ref()
  local onto_name
  if onto_ref then
    onto_name = vim.startswith(onto_ref, "refs/heads/") and onto_ref:sub(12) or onto_ref
  else
    onto_name = onto_id:tostring(8)
  end

  ---@type Fugit2GitRebase
  local rebase = {
    repo = repo,
    operations = operations,
    last_commit = git2.Commit.new(last_commit[0]),
    onto_id = onto_id,
    onto_name = onto_name,
  }
  setmetatable(rebase, GitRebase)
  return rebase, 0
end

-- Init rebase
---@param repo GitRepository
---@param branch GitAnnotatedCommit?
---@param upstream GitAnnotatedCommit?
---@param onto GitAnnotatedCommit?
---@return Fugit2GitRebase?
---@return GIT_ERROR
function GitRebase.init(repo, branch, upstream, onto)
  local rebase, operations, err

  if not onto then
    onto = upstream
  end
  assert(onto ~= nil, "Upstream or onto must be set")

  if not branch then
    local head, head_branch

    head, err = repo:head()
    if not head then
      return nil, err
    end

    head_branch, err = repo:annotated_commit_from_ref(head)
    if not head_branch then
      return nil, err
    end

    branch = head_branch
  end

  operations, err =
    rebase_init_operations(repo.repo, branch and branch.commit, upstream and upstream.commit, onto and onto.commit)
  if not operations then
    goto fugit2_git_rebase_init_cleanup
  end

  rebase, err = rebase_init_inmemory(repo, onto, operations)

  ::fugit2_git_rebase_init_cleanup::
  return rebase, err
end

-- ========================================
-- | Libgit2 override for inmemory rebase |
-- ========================================

---@param upstream GitAnnotatedCommit?
---@param onto GitAnnotatedCommit?
---@return string rebase_onto_name
function M.git_rebase_onto_name(upstream, onto)
  if not onto then
    onto = upstream
  end
  assert(onto ~= nil, "Upstream or onto must be set")

  local onto_ref = onto:ref()
  local onto_name
  if onto_ref then
    onto_name = vim.startswith(onto_ref, "refs/heads/") and onto_ref:sub(12) or onto_ref
  else
    onto_name = onto:id():tostring(8)
  end

  return onto_name
end

return M
