local ffi = require "ffi"
local libgit2 = require "fugit2.libgit2"

--- Libgit2 init
local libgit2_init_count = 0

if libgit2_init_count == 0 then
  libgit2_init_count = libgit2.C.git_libgit2_init()
end

-- ========================
-- | Libgit2 Enum section |
-- ========================

local GIT_REFERENCE_STRING = {
  "INVALID",
  "DIRECT",
  "SYMBOLIC",
  "DIRECT/SYMBOLIC",
}

---@enum GIT_REFERENCE_NAMESPACE
local GIT_REFERENCE_NAMESPACE = {
  NONE   = 0, -- Normal ref, no namespace
  BRANCH = 1, -- Reference is in Branch namespace
  TAG    = 2, -- Reference is in Tag namespace
  REMOTE = 3, -- Reference is in Remote namespace
  NOTE   = 4, -- Reference is in Note namespace
}

---@enum GIT_STATUS_SHORT
local GIT_STATUS_SHORT = {
  UNCHANGED  = 0,
  ADD        = 1,
  MODIFIED   = 2,
  DELETED    = 3,
  RENAMED    = 4,
  TYPECHANGE = 5,
  UNREADABLE = 6,
  IGNORED    = 7,
  CONFLICTED = 8,
}

local GIT_STATUS_SHORT_STRING = {
  "UNCHANGED",
  "ADD",
  "MODIFIED",
  "DELETED",
  "RENAMED",
  "TYPECHANGE",
  "UNREADABLE",
  "IGNORED",
  "CONFLICTED",
}


-- =====================
-- | Class definitions |
-- =====================

---@class GitRepository
---@field repo ffi.cdata* libgit2 git_repository struct
---@field path string git repository path
local Repository = {}
Repository.__index = Repository


--- Creates new Repository object
---@param git_repository ffi.cdata* libgit2 git repository, own cdata
---@return GitRepository
function Repository.new (git_repository)
  local repo = {repo = git_repository}
  setmetatable(repo, Repository)

  local c_path = libgit2.C.git_repository_path(git_repository[0])
  repo.path = ffi.string(c_path)

  ffi.gc(repo.repo, function (c_repo)
    libgit2.C.git_repository_free(c_repo[0])
  end)

  return repo
end

---@class GitReference
---@field ref ffi.cdata* libgit2 git_reference type
---@field name string Reference Refs full name
---@field type GIT_REFERENCE Reference type
---@field namespace GIT_REFERENCE_NAMESPACE Reference namespace if available
local Reference = {}
Reference.__index = Reference


-- Creates new Reference object
---@param git_reference ffi.cdata* libgit2 git_reference, own cdata
---@return GitReference
function Reference.new (git_reference)
  local ref = { ref = git_reference, namespace = GIT_REFERENCE_NAMESPACE.NONE }
  setmetatable(ref, Reference)

  local c_name = libgit2.C.git_reference_name(git_reference[0])
  ref.name = ffi.string(c_name)

  if vim.startswith(ref.name, "refs/") then
    local namespace = string.sub(ref.name, string.len("refs/") + 1)
    if vim.startswith(namespace, "heads/") then
      ref.namespace = GIT_REFERENCE_NAMESPACE.BRANCH
    elseif vim.startswith(namespace, "tags/") then
      ref.namespace = GIT_REFERENCE_NAMESPACE.TAG
    elseif vim.startswith(namespace, "remotes/") then
      ref.namespace = GIT_REFERENCE_NAMESPACE.REMOTE
    elseif vim.startswith(namespace, "notes/") then
      ref.namespace = GIT_REFERENCE_NAMESPACE.NOTE
    end
  end

  local c_type = libgit2.C.git_reference_type(git_reference[0])
  ref.type = c_type

  -- ffi garbage collector
  ffi.gc(ref.ref, function (c_ref)
    libgit2.C.git_reference_free(c_ref[0])
  end)

  return ref
end



-- =======================
-- | Reference funcionts |
-- =======================


function Reference:__tostring()
  return string.format("Git Ref (%s): %s", GIT_REFERENCE_STRING[self.type+1], self.name)
end


-- Transforms the reference name into a name "human-readable" version.
---@return string # Shorthand for ref
function Reference:shorthand()
  local c_name = libgit2.C.git_reference_shorthand(self.ref[0])
  return ffi.string(c_name)
end


-- Gets target for a GitReference
---@return ffi.cdata*?
---@return integer Git Error code
function Reference:target()
  if self.type == libgit2.GIT_REFERENCE.SYMBOLIC then
    local resolved = libgit2.git_reference_double_pointer()

    local ret = libgit2.C.git_reference_resolve(resolved, self.ref[0])
    if ret ~=0 then
      return nil, ret
    end

    local oid = libgit2.C.git_reference_target(resolved[0])
    libgit2.C.git_reference_free(resolved[0])

    return oid, 0
  elseif self.type ~= 0 then
    local oid = libgit2.C.git_reference_target(self.ref[0])
    return oid, 0
  end

  return nil, 0
end


-- Gets upstream for a branch
---@return GitReference? Reference git upstream reference
---@return GIT_ERROR 
function Reference:branch_upstream()
  if self.namespace ~= GIT_REFERENCE_NAMESPACE.BRANCH then
    return nil, 0
  end

  local c_ref = libgit2.git_reference_double_pointer()

  local ret = libgit2.C.git_branch_upstream(c_ref, self.ref[0]);

  if ret ~= 0 then
    return nil, ret
  end

  return Reference.new(c_ref), 0
end


-- ====================
-- | Status functions |
-- ====================

function GIT_STATUS_SHORT.tostring(status)
  return GIT_STATUS_SHORT_STRING[status+1]
end


-- ========================
-- | Repository functions |
-- ========================


---@class GitStatusItem
---@field path string File path
---@field new_path string? New file path in case of rename
---@field worktree_status GIT_STATUS_SHORT Git status in worktree to index
---@field index_status GIT_STATUS_SHORT Git status in index to head


---@class GitStatusResult
---@field head string
---@field head_is_detached boolean
---@field ahead integer
---@field bedhind integer
---@field status GitStatusItem[]


function Repository:__tostring()
  return string.format("Git Repository: %s", self.path)
end


-- Creates Git repository
---@param path string Path to repository
---@return GitRepository?
function Repository.open (path)
  local git_repo = libgit2.git_repository_double_pointer()

  local ret = libgit2.C.git_repository_open(git_repo, path)
  if ret ~= 0 then
    return nil
  end

  return Repository.new(git_repo)
end


-- Checks a Repository is empty or not
---@return boolean is_empty Whether this git repo is empty
function Repository:is_empty()
  local ret = libgit2.C.git_repository_is_empty(self.repo[0])
  if ret == 1 then
    return true
  elseif ret == 0 then
    return false
  else
    error("Repository is corrupted")
  end
end


-- Checks a Repository is bare or not
---@return boolean is_bare Whether this git repo is bare repository
function Repository:is_bare()
  local ret = libgit2.C.git_repository_is_bare(self.repo[0])
  return ret == 1
end


-- Checks a Repository HEAD is detached or not
---@return boolean is_head_detached Whether this git repo head detached
function Repository:is_head_detached()
  local ret = libgit2.C.git_repository_head_detached(self.repo[0])
  return ret == 1
end


-- Retrieves reference pointed at by HEAD.
---@return GitReference?
---@return GIT_ERROR
function Repository:head()
  local c_ref = libgit2.git_reference_double_pointer()

  local ret = libgit2.C.git_repository_head(c_ref, self.repo[0])
  if ret == libgit2.GIT_ERROR.GIT_EUNBORNBRANCH or ret == libgit2.GIT_ERROR.GIT_ENOTFOUND then
    return nil, ret
  elseif ret ~= 0 then
    return nil, ret
  end

  return Reference.new(c_ref), 0
end


-- Caculates ahead and behind information.
---@param local_commit ffi.cdata* The commit which is considered the local or current state.
---@param upstream_commit ffi.cdata* The commit which is considered upstream.
---@return number? ahead Unique ahead commits.
---@return number? behind Unique behind commits.
---@return GIT_ERROR error Error code.
function Repository:ahead_behind(local_commit, upstream_commit)
  local c_ahead = ffi.new("size_t[2]")

  local ret = libgit2.C.git_graph_ahead_behind(
    c_ahead, c_ahead + 1, self.repo[0], local_commit, upstream_commit
  )

  if ret ~= 0 then
    return nil, nil, ret
  end

  return tonumber(c_ahead[0]), tonumber(c_ahead[1]), 0
end


-- Reads the status of the repository and returns a dictionary.
-- with file paths as keys and status flags as values.
---@return GitStatusResult? status_result git status result.
---@return integer return_code Return code.
function Repository:status()
  ---@type GIT_ERROR
  local error

  ---type number
  local ahead, behind = 0, 0

  local opts = ffi.new("git_status_options[1]")
  libgit2.C.git_status_options_init(opts, 1)
  opts[0].show = libgit2.GIT_STATUS_SHOW.INDEX_AND_WORKDIR
  opts[0].flags = bit.bor(
    libgit2.GIT_STATUS_OPT.INCLUDE_UNTRACKED,
    libgit2.GIT_STATUS_OPT.RENAMES_HEAD_TO_INDEX,
    libgit2.GIT_STATUS_OPT.SORT_CASE_SENSITIVELY
  )

  local status = ffi.new("struct git_status_list*[1]")
  error = libgit2.C.git_status_list_new(status, self.repo[0], opts)
  if error ~= 0 then
    return nil, error
  end

  -- Get Head information
  local repo_head
  repo_head, error = self:head()
  if repo_head == nil then
    return nil, error
  end

  -- Get upstream information
  local repo_upstream
  repo_upstream, error = repo_head:branch_upstream()
  if repo_upstream ~= nil then
    local commit_local, _ = repo_head:target()
    local commit_upstream, _ = repo_upstream:target()

    if commit_upstream ~= nil and commit_local ~= nil then
      local nilable_ahead, nilable_behind, _ = self:ahead_behind(commit_local, commit_upstream)
      if nilable_ahead ~= nil and nilable_behind ~= nil then
        ahead, behind = nilable_ahead, nilable_behind
      end
    end
  end

  ---@type GitStatusResult
  local result = {
    head             = repo_head:shorthand(),
    head_is_detached = self:is_head_detached(),
    ahead            = ahead,
    bedhind          = behind,
    status           = {}
  }

  local n_entry = tonumber(libgit2.C.git_status_list_entrycount(status[0]))

  -- Iterate through git status list
  for i = 0,n_entry-1 do
    local entry = libgit2.C.git_status_byindex(status[0], i)
    if entry == nil or entry.status == libgit2.GIT_STATUS.CURRENT then
      goto git_status_list_continue
    end

    ---@type GitStatusItem
    local status_item = {
      path            = "",
      worktree_status = GIT_STATUS_SHORT.UNCHANGED,
      index_status    = GIT_STATUS_SHORT.UNCHANGED,
    }
    ---@type string
    local wt_old_path, wt_new_path, index_old_path, index_new_path

    if entry.index_to_workdir ~= nil then
      wt_old_path = ffi.string(entry.index_to_workdir.old_file.path)
      wt_new_path = ffi.string(entry.index_to_workdir.new_file.path)

      status_item.path = wt_old_path

      if bit.band(entry.status, libgit2.GIT_STATUS.WT_NEW) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.ADD
      elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_MODIFIED) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.MODIFIED
      elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_DELETED) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.DELETED
      elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_RENAMED) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.RENAMED
        status_item.new_path = wt_new_path
      elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_TYPECHANGE) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.TYPECHANGE
      elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_UNREADABLE) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.UNREADABLE
      elseif bit.band(entry.status, libgit2.GIT_STATUS.IGNORED) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.IGNORED
      elseif bit.band(entry.status, libgit2.GIT_STATUS.CONFLICTED) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.CONFLICTED
      end
    end

    if entry.head_to_index ~= nil then
      index_old_path = ffi.string(entry.head_to_index.old_file.path)
      index_new_path = ffi.string(entry.head_to_index.new_file.path)

      status_item.path = index_old_path

      if bit.band(entry.status, libgit2.GIT_STATUS.INDEX_NEW) ~= 0 then
        status_item.index_status = GIT_STATUS_SHORT.ADD
      elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_MODIFIED) ~= 0 then
        status_item.index_status = GIT_STATUS_SHORT.MODIFIED
      elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_DELETED) ~=0 then
        status_item.index_status = GIT_STATUS_SHORT.DELETED
      elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_RENAMED) ~=0 then
        status_item.index_status = GIT_STATUS_SHORT.RENAMED
        status_item.new_path = index_new_path
      elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_TYPECHANGE) ~=0 then
        status_item.index_status = GIT_STATUS_SHORT.TYPECHANGE
      end
    end

    table.insert(result.status, status_item)
    ::git_status_list_continue::
  end

  -- free C resources
  libgit2.C.git_status_list_free(status[0])

  return result, 0
end

-- ==================
-- | Git2Module     |
-- ==================

---@class Git2Module
local M = {}

M.Repository = Repository
M.Reference = Reference


M.GIT_REFERENCE = libgit2.GIT_REFERENCE
M.GIT_REFERENCE_NAMESPACE = GIT_REFERENCE_NAMESPACE
M.GIT_STATUS_SHORT = GIT_STATUS_SHORT


M.head = Repository.head
M.status = Repository.status


function M.destroy()
  libgit2_init_count = libgit2.C.git_libgit2_shutdown()
end


return M
