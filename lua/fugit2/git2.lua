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
  ADD        = 0,
  MODIFIED   = 1,
  DELETED    = 2,
  RENAMED    = 3,
  TYPECHANGE = 4,
  UNREADABLE = 5,
  UNTRACKED  = 6,
  IGNORED    = 7,
  CONFLICTED = 8,
}

local GIT_STATUS_SHORT_STRING = {
  "ADD",
  "MODIFIED",
  "DELETED",
  "RENAMED",
  "TYPECHANGE",
  "UNREADABLE",
  "UNTRACKED",
  "IGNORED",
  "CONFLICTED"
}


-- =====================
-- | Class definitions |
-- =====================

---@class Repository
---@field repo ffi.cdata* libgit2 git_repository struct
---@field path string git repository path
local Repository = {}


--- Creates new Repository object
---@param git_repository ffi.cdata* libgit2 git repository
---@return Repository
function Repository.new (git_repository)
  local repo = {repo = git_repository}
  setmetatable(repo, Repository)

  local c_path = libgit2.C.git_repository_path(git_repository[0])
  repo.path = ffi.string(c_path)

  return repo
end

---@class Reference
---@field ref ffi.cdata* libgit2 git_reference type
---@field name string Reference Refs full name
---@field type GIT_REFERENCE Reference type
---@field namespace GIT_REFERENCE_NAMESPACE Reference namespace if available
local Reference = {}


-- Creates new Reference object
---@param git_reference ffi.cdata* libgit2 git_reference
---@return Reference
function Reference.new (git_reference)
  local ref = {ref = git_reference, namespace = GIT_REFERENCE_NAMESPACE.NONE}
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

  return ref
end


---@class StatusItem
---@field status GIT_STATUS_SHORT GIT status of file
---@field path string File path
---@field new_path string? Old File path
local StatusItem = {}

---@class StatusResult
---@field worktree StatusItem[]
---@field index StatusItem[]
local StatusResult = {}


-- =======================
-- | Reference funcionts |
-- =======================


function Reference.__tostring(ref)
  return string.format("Git Ref (%s): %s", GIT_REFERENCE_STRING[ref.type+1], ref.name)
end


--- Transforms the reference name into a name "human-readable" version.
---@param ref Reference
---@return string # Shorthand for ref
function Reference.shorthand(ref)
  local c_name = libgit2.C.git_reference_shorthand(ref.ref[0])
  return ffi.string(c_name)
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


function Repository.__tostring(repo)
  return string.format("Git Repository: %s", repo.path)
end


--- Creates Git repository
---@param path string Path to repository
---@return Repository?
function Repository.open (path)
  local git_repo = ffi.new("struct git_repository*[1]")

  local ret = libgit2.C.git_repository_open(git_repo, path)
  if ret ~= 0 then
    return nil
  end

  ffi.gc(git_repo, function (repo)
    libgit2.C.git_repository_free(repo[0])
  end)

  return Repository.new(git_repo)
end


--- Checks a Repository is empty or not
---@param repo Repository input repository
---@return boolean is_empty Whether this git repo is empty
function Repository.is_empty (repo)
  local ret = libgit2.C.git_repository_is_empty(repo.repo[0])
  if ret == 1 then
    return true
  elseif ret == 0 then
    return false
  else
    error("Repository is corrupted")
  end
end


--- Checks a Repository is bare or not
---@param repo Repository repository
---@return boolean is_bare Whether this git repo is bare repository
function Repository.is_bare(repo)
  local ret = libgit2.C.git_repository_is_bare(repo.repo[0])
  return ret == 1
end


-- Checks a Repository HEAD is detached or not
---@param repo Repository repository
---@return boolean is_head_detached Whether this git repo head detached
function Repository.is_head_detached(repo)
  local ret = libgit2.C.git_repository_head_detached(repo.repo[0])
  return ret == 1
end


-- Retrieves reference pointed at by HEAD.
---@param repo Repository input repository
---@return Reference?
function Repository.head(repo)
  local c_ref = ffi.new("struct git_reference*[1]")

  local ret = libgit2.C.git_repository_head(c_ref, repo.repo[0])
  if ret == libgit2.GIT_ERROR.GIT_EUNBORNBRANCH or ret == libgit2.GIT_ERROR.GIT_ENOTFOUND then
    return nil
  elseif ret ~= 0 then
    error("Failed to get head")
  end

  ffi.gc(c_ref, function (ref)
    libgit2.C.git_reference_free(ref[0])
  end)

  return Reference.new(c_ref)
end


-- Reads the status of the repository and returns a dictionary
-- with file paths as keys and status flags as values.
---@param repo Repository repository
---@return StatusResult? status_result List of status
---@return integer return_code Return code
function Repository.status(repo)

  local opts = ffi.new("git_status_options[1]")
  libgit2.C.git_status_options_init(opts, 1)
  opts[0].show = libgit2.GIT_STATUS_SHOW.INDEX_AND_WORKDIR
  opts[0].flags = bit.bor(
    libgit2.GIT_STATUS_OPT.INCLUDE_UNTRACKED,
    -- libgit2.GIT_STATUS_OPT.RENAMES_HEAD_TO_INDEX,
    libgit2.GIT_STATUS_OPT.SORT_CASE_SENSITIVELY
  )

  local status = ffi.new("struct git_status_list*[1]")
  local ret = libgit2.C.git_status_list_new(status, repo.repo[0], opts)
  if ret ~= 0 then
    return nil, ret
  end

  ---@type StatusResult
  local result = {
    index    = {},
    worktree = {},
  }

  local n_entry = tonumber(libgit2.C.git_status_list_entrycount(status[0]))

  -- Iterate through git status list
  for i = 0,n_entry-1 do
    local entry = libgit2.C.git_status_byindex(status[0], i)
    if entry == nil or entry.status == libgit2.GIT_STATUS.CURRENT then
      goto git_status_list_continue
    end

    ---@type StatusItem
    local index_status_item
    ---@type StatusItem
    local worktree_status_item
    ---@type string
    local old_path
    ---@type string
    local new_path

    if entry.head_to_index ~= nil then
      old_path = ffi.string(entry.head_to_index.old_file.path)
      new_path = ffi.string(entry.head_to_index.new_file.path)
    end

    if bit.band(entry.status, libgit2.GIT_STATUS.INDEX_NEW) ~= 0 then
      index_status_item = {
        status = GIT_STATUS_SHORT.ADD,
        path   = new_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_MODIFIED) ~= 0 then
      index_status_item = {
        status = GIT_STATUS_SHORT.MODIFIED,
        path   = old_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_DELETED) ~=0 then
      index_status_item = {
        status = GIT_STATUS_SHORT.DELETED,
        path   = old_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_RENAMED) ~=0 then
      index_status_item = {
        status   = GIT_STATUS_SHORT.RENAMED,
        path     = old_path,
        new_path = new_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.INDEX_TYPECHANGE) ~=0 then
      index_status_item = {
        status = GIT_STATUS_SHORT.TYPECHANGE,
        path = old_path
      }
    end

    table.insert(result.index, index_status_item)

    if entry.index_to_workdir ~= nil then
      old_path = ffi.string(entry.index_to_workdir.old_file.path)
      new_path = ffi.string(entry.index_to_workdir.new_file.path)
    end

    if bit.band(entry.status, libgit2.GIT_STATUS.WT_NEW) ~= 0 then
      worktree_status_item = {
        status = GIT_STATUS_SHORT.UNTRACKED,
        path   = new_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_MODIFIED) ~= 0 then
      worktree_status_item = {
        status = GIT_STATUS_SHORT.MODIFIED,
        path   = old_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_DELETED) ~= 0 then
      worktree_status_item = {
        status = GIT_STATUS_SHORT.DELETED,
        path   = old_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_RENAMED) ~= 0 then
      worktree_status_item = {
        status   = GIT_STATUS_SHORT.RENAMED,
        path     = old_path,
        new_path = new_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_TYPECHANGE) ~= 0 then
      worktree_status_item = {
        status = GIT_STATUS_SHORT.TYPECHANGE,
        path   = old_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.WT_UNREADABLE) ~= 0 then
      worktree_status_item = {
        status = GIT_STATUS_SHORT.UNREADABLE,
        path   = old_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.IGNORED) ~= 0 then
      worktree_status_item = {
        status = GIT_STATUS_SHORT.IGNORED,
        path   = old_path
      }
    elseif bit.band(entry.status, libgit2.GIT_STATUS.CONFLICTED) ~= 0 then
      worktree_status_item = {
        status = GIT_STATUS_SHORT.CONFLICTED,
        path   = old_path
      }
    end

    table.insert(result.worktree, worktree_status_item)

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
