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
  UNTRACKED  = 1,
  ADD        = 2,
  MODIFIED   = 3,
  DELETED    = 4,
  RENAMED    = 5,
  TYPECHANGE = 6,
  UNREADABLE = 7,
  IGNORED    = 8,
  CONFLICTED = 9,
}

local GIT_STATUS_SHORT_STRING = {
  "UNCHANGED",
  "UNTRACKED",
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
---@field repo ffi.cdata* libgit2 struct git_repository*[1]
---@field path string git repository path
local Repository = {}
Repository.__index = Repository


--- Creates new Repository object
---@param git_repository ffi.cdata* libgit2 struct git_repository*[1], own cdata
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


---@class GitObject
---@field obj ffi.cdata* libgit2 struct git_object*[1]
local Object = {}
Object.__index = Object


---@class GitObjectId
---@field oid ffi.cdata* libgit2 git_oid struct
local ObjectId = {}
ObjectId.__index = ObjectId


---@class GitCommit
---@field commit ffi.cdata* libgit2 git_commit struct
local Commit = {}
Commit.__index = Commit


---@class GitReference
---@field ref ffi.cdata* libgit2 git_reference type
---@field name string Reference Refs full name
---@field type GIT_REFERENCE Reference type
---@field namespace GIT_REFERENCE_NAMESPACE Reference namespace if available
local Reference = {}
Reference.__index = Reference


---@class GitIndex
---@field index ffi.cdata* libgit2 struct git_index*[1]
local Index = {}
Index.__index = Index


-- ========================
-- | Git Object functions |
-- ========================


---@param c_object ffi.cdata* libgit2 struct git_object*[1], own cdata.
---@return GitObject
function Object.new(c_object)
  local git_object = { obj = c_object }
  setmetatable(git_object, Object)

  ffi.gc(git_object.obj, function(c_obj)
    libgit2.C.git_object_free(c_obj[0])
  end)

  return git_object
end


-- Get the id (SHA1) of a repository object.
---@return GitObjectId
function Object:id()
  local oid = libgit2.C.git_object_id(self.obj[0])
  return ObjectId.new(oid)
end


-- ======================
-- | ObjectId functions |
-- ======================

---@param oid ffi.cdata*
function ObjectId.new (oid)
  local object_id = { oid = oid }
  setmetatable(object_id, ObjectId)
  return object_id
end


---@param n integer number of git id
---@return string
function ObjectId:tostring(n)
  if n < 0 or n > 40 then
    n = 41
  end

  local c_buf = ffi.new("char[?]", n+1)
  libgit2.C.git_oid_tostr(c_buf, n+1, self.oid)
  return ffi.string(c_buf)
end


---@return string
function ObjectId:__tostring()
  return self:tostring(8)
end


-- ====================
-- | Commit functions |
-- ====================


-- Init GitCommit.
---@param git_commit ffi.cdata* libgit2 git_commit, this owns the data.
---@return GitCommit
function Commit.new (git_commit)
  local commit = { commit = git_commit }
  setmetatable(commit, Commit)

  -- ffi garbage collector
  ffi.gc(commit.commit, function(c_commit)
    libgit2.C.git_commit_free(c_commit[0])
  end)

  return commit
end


-- Gets GitCommit messages.
---@return string
function Commit:message()
  local c_char = libgit2.C.git_commit_message(self.commit[0])
  return vim.trim(ffi.string(c_char))
end


-- =======================
-- | Reference functions |
-- =======================


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
---@return GitObjectId?
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

    return ObjectId.new(oid), 0
  elseif self.type ~= 0 then
    local oid = libgit2.C.git_reference_target(self.ref[0])
    return ObjectId.new(oid), 0
  end

  return nil, 0
end


-- Recursively peel reference until object of the specified type is found.
---@param type GIT_OBJECT
---@return GitObject?
---@return integer Git Error code
function Reference:peel(type)
  local c_object = ffi.new("git_object *[1]")

  local ret = libgit2.C.git_reference_peel(c_object, self.ref[0], type);
  if ret ~= 0 then
    return nil, ret
  end

  return Object.new(c_object), 0
end


-- Gets upstream for a branch.
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


-- ===================
-- | Index functions |
-- ===================


-- Inits new GitIndex object.
---@param index ffi.cdata* struct git_index*[1], own cdata
---@return GitIndex
function Index.new (index)
  local git_index = { index = index }
  setmetatable(git_index, Index)

  ffi.gc(git_index.index, function (c_index)
    libgit2.C.git_index_free(c_index[0])
  end)

  return git_index
end


-- Updates the contents of an existing index object.
---@param force boolean Performs hard read or not?
---@return GIT_ERROR
function Index:read (force)
  return libgit2.C.git_index_read(self.index[0], force and 1 or 0)
end


-- Writes index from memory to file.
---@return GIT_ERROR
function Index:write()
  return libgit2.C.git_index_write(self.index[0])
end


-- Adds path to index.
---@param path string File path to be added.
---@return GIT_ERROR
function Index:add_bypath(path)
  return libgit2.C.git_index_add_bypath(self.index[0], path)
end


-- Removes path from index.
---@param path string File path to be removed.
---@return GIT_ERROR
function Index:remove_bypath(path)
  return libgit2.C.git_index_remove_bypath(self.index[0], path)
end


-- ====================
-- | Status functions |
-- ====================

---@return string
function GIT_STATUS_SHORT.tostring(status)
  return GIT_STATUS_SHORT_STRING[status+1]
end


---@return string
function GIT_STATUS_SHORT.toshort(status)
  if status == GIT_STATUS_SHORT.UNTRACKED then
    return "?"
  elseif status == GIT_STATUS_SHORT.UNCHANGED then
    return "-"
  elseif status == GIT_STATUS_SHORT.IGNORED then
    return "!"
  end
  return GIT_STATUS_SHORT_STRING[status+1]:sub(1, 1)
end


-- ========================
-- | Repository functions |
-- ========================


---@class GitStatusItem
---@field path string File path
---@field new_path string? New file path in case of rename
---@field worktree_status GIT_STATUS_SHORT Git status in worktree to index
---@field index_status GIT_STATUS_SHORT Git status in index to head


---@class GitStatusUpstream
---@field name string
---@field oid string
---@field message string
---@field ahead integer
---@field behind integer


---@class GitStatusHead
---@field name string
---@field oid string
---@field message string
---@field is_detached boolean


---@class GitStatusResult
---@field head GitStatusHead
---@field upstream GitStatusUpstream?
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


-- Gets commit from a reference.
---@param oid GitObjectId
---@return GitCommit?
---@return GIT_ERROR
function Repository:commit_lookup (oid)
  local c_commit = ffi.new("git_commit*[1]")

  local ret = libgit2.C.git_commit_lookup(c_commit, self.repo[0], oid.oid)
  if ret ~= 0 then
    return nil, ret
  end

  return Commit.new(c_commit), 0
end


-- Gets repository index.
---@return GitIndex?
---@return GIT_ERROR
function Repository:index ()
  local c_index = ffi.new("git_index*[1]")

  local ret = libgit2.C.git_repository_index(c_index, self.repo[0])
  if ret ~= 0 then
    return nil, ret
  end

  return Index.new(c_index), 0
end


-- Updates some entries in the index from the target commit tree.
---@param paths string[]
---@return GIT_ERROR
function Repository:reset_default(paths)
  local head, ret = self:head()
  if head == nil then
    return ret
  else
    local commit, err = head:peel(libgit2.GIT_OBJECT.COMMIT)
    if commit == nil then
      return err
    elseif #paths > 0 then
      local c_paths = ffi.new("const char *[?]", #paths)
      local strarray = ffi.new("git_strarray_readonly[1]")

      for i, p in ipairs(paths) do
        c_paths[i-1] = p
      end

      strarray[0].strings = c_paths
      strarray[0].count = #paths

      return libgit2.C.git_reset_default(self.repo[0], commit.obj[0], strarray);
    end
    return 0
  end
end


-- Reads status of a given file path.
---@param path string Git file path.
---@return GIT_STATUS_SHORT worktree_status Git Status in worktree.
---@return GIT_STATUS_SHORT index_status Git Status in index.
---@return GIT_ERROR return_code Git return code.
function Repository:status_file(path)
  local worktree_status, index_status = GIT_STATUS_SHORT.UNCHANGED, GIT_STATUS_SHORT.UNCHANGED
  local c_status = ffi.new("unsigned int[1]")

  local ret = libgit2.C.git_status_file(c_status, self.repo[0], path)
  if ret ~= 0 then
    return worktree_status, index_status, ret
  end

  local status = tonumber(c_status[0])
  if status ~= nil then
    if bit.band(status, libgit2.GIT_STATUS.WT_NEW) ~= 0 then
      worktree_status = GIT_STATUS_SHORT.UNTRACKED
      index_status = GIT_STATUS_SHORT.UNTRACKED
    elseif bit.band(status, libgit2.GIT_STATUS.WT_MODIFIED) ~= 0 then
      worktree_status = GIT_STATUS_SHORT.MODIFIED
    elseif bit.band(status, libgit2.GIT_STATUS.WT_DELETED) ~= 0 then
      worktree_status = GIT_STATUS_SHORT.DELETED
    elseif bit.band(status, libgit2.GIT_STATUS.WT_TYPECHANGE) ~= 0 then
      worktree_status = GIT_STATUS_SHORT.TYPECHANGE
    elseif bit.band(status, libgit2.GIT_STATUS.WT_UNREADABLE) ~= 0 then
      worktree_status = GIT_STATUS_SHORT.UNREADABLE
    elseif bit.band(status, libgit2.GIT_STATUS.IGNORED) ~= 0 then
      worktree_status = GIT_STATUS_SHORT.IGNORED
    elseif bit.band(status, libgit2.GIT_STATUS.CONFLICTED) ~= 0 then
      worktree_status = GIT_STATUS_SHORT.CONFLICTED
    end

    if bit.band(status, libgit2.GIT_STATUS.INDEX_NEW) ~= 0 then
      index_status = GIT_STATUS_SHORT.ADD
    elseif bit.band(status, libgit2.GIT_STATUS.INDEX_MODIFIED) ~= 0 then
      index_status = GIT_STATUS_SHORT.MODIFIED
    elseif bit.band(status, libgit2.GIT_STATUS.INDEX_DELETED) ~=0 then
      index_status = GIT_STATUS_SHORT.DELETED
    elseif bit.band(status, libgit2.GIT_STATUS.INDEX_TYPECHANGE) ~= 0 then
      index_status = GIT_STATUS_SHORT.TYPECHANGE
    end
  end

  return worktree_status, index_status, 0
end


-- Reads the status of the repository and returns a dictionary.
-- with file paths as keys and status flags as values.
---@return GitStatusResult? status_result git status result.
---@return integer return_code Return code.
function Repository:status()
  ---@type GIT_ERROR
  local error

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

  local repo_head_oid, _ = repo_head:target()
  local repo_head_oid_str, repo_head_msg = "", ""
  if repo_head_oid ~= nil then
    repo_head_oid_str = tostring(repo_head_oid)
    repo_head_msg = self:commit_lookup(repo_head_oid):message()
  end

  ---@type GitStatusResult
  local result = {
    head = {
      name        = repo_head:shorthand(),
      oid         = repo_head_oid_str,
      message     = repo_head_msg,
      is_detached = self:is_head_detached(),
    },
    status = {}
  }

  -- Get upstream information
  local repo_upstream
  repo_upstream, error = repo_head:branch_upstream()
  if repo_upstream ~= nil then
    ---@type number
    local ahead, behind = 0, 0
    local commit_local = repo_head_oid
    local commit_upstream, _ = repo_upstream:target()

    if commit_upstream ~= nil and commit_local ~= nil then
      local nilable_ahead, nilable_behind, _ = self:ahead_behind(commit_local.oid, commit_upstream.oid)
      if nilable_ahead ~= nil and nilable_behind ~= nil then
        ahead, behind = nilable_ahead, nilable_behind
      end
    end

    local oid_str, msg = "", ""
    if commit_upstream ~= nil then
      oid_str = tostring(commit_upstream)
      msg = self:commit_lookup(commit_upstream):message()
    end

    result.upstream = {
      name    = repo_upstream:shorthand(),
      oid     = oid_str,
      message =  msg,
      ahead   = ahead,
      behind  = behind
    }
  end

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
    local old_path, new_path

    if entry.index_to_workdir ~= nil then
      old_path = ffi.string(entry.index_to_workdir.old_file.path)
      new_path = ffi.string(entry.index_to_workdir.new_file.path)

      status_item.path = old_path

      if bit.band(entry.status, libgit2.GIT_STATUS.WT_NEW) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.UNTRACKED
        status_item.index_status = GIT_STATUS_SHORT.UNTRACKED
      elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_MODIFIED) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.MODIFIED
      elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_DELETED) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.DELETED
      elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_RENAMED) ~= 0 then
        status_item.worktree_status = GIT_STATUS_SHORT.RENAMED
        status_item.new_path = new_path
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
      old_path = ffi.string(entry.head_to_index.old_file.path)
      new_path = ffi.string(entry.head_to_index.new_file.path)

      status_item.path = old_path

      if bit.band(entry.status, libgit2.GIT_STATUS.INDEX_NEW) ~= 0 then
        status_item.index_status = GIT_STATUS_SHORT.ADD
      elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_MODIFIED) ~= 0 then
        status_item.index_status = GIT_STATUS_SHORT.MODIFIED
      elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_DELETED) ~=0 then
        status_item.index_status = GIT_STATUS_SHORT.DELETED
      elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_RENAMED) ~=0 then
        status_item.index_status = GIT_STATUS_SHORT.RENAMED
        status_item.new_path = new_path
      elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_TYPECHANGE) ~= 0 then
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
