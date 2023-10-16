local ffi = require "ffi"
local libgit2 = require "fugit2.libgit2"


-- ========================
-- | Libgit2 ENUM section |
-- ========================

---@enum GIT_REFERENCE_TYPE
local GIT_REFERENCE_TYPE = {
	INVALID  = 1, -- Invalid reference
	DIRECT   = 2, -- A reference that points at an object id
	SYMBOLIC = 3, -- A reference that points at another reference
	ALL      = 4  -- BOTH
}

local GIT_REFERENCE_TYPE_STR = {
  "INVALID",
  "DIRECT",
  "SYMBOLIC",
  "DIRECT/SYMBOLIC"
}

---@enum GIT_REFERENCE_NAMESPACE
local GIT_REFERENCE_NAMESPACE = {
  NONE   = 0, -- Normal ref, no namespace
  BRANCH = 1, -- Reference is in Branch namespace
  TAG    = 2, -- Reference is in Tag namespace
  REMOTE = 3, -- Reference is in Remote namespace
  NOTE   = 4  -- Reference is in Note namespace
}


--- Libgit2 init
local libgit2_init_count = 0

if libgit2_init_count == 0 then
 libgit2_init_count = libgit2.git_libgit2_init()
end


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

  local c_path = libgit2.git_repository_path(git_repository[0])
  repo.path  = ffi.string(c_path)

  return repo
end

---@class Reference
---@field ref ffi.cdata* libgit2 git_reference type
---@field name string Reference Refs full name
---@field type GIT_REFERENCE_TYPE Reference type
---@field namespace GIT_REFERENCE_NAMESPACE Reference namespace if available
local Reference = {}


-- Creates new Reference object
---@param git_reference ffi.cdata* libgit2 git_reference
---@return Reference
function Reference.new (git_reference)
  local ref = {ref = git_reference, namespace = GIT_REFERENCE_NAMESPACE.NONE}
  setmetatable(ref, Reference)

  local c_name = libgit2.git_reference_name(git_reference[0])
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

  local c_type = libgit2.git_reference_type(git_reference[0])
  if c_type == libgit2.GIT_REFERENCE_INVALID then
    ref.type = GIT_REFERENCE_TYPE.INVALID
  elseif c_type == libgit2.GIT_REFERENCE_DIRECT then
    ref.type = GIT_REFERENCE_TYPE.DIRECT
  elseif c_type == libgit2.GIT_REFERENCE_SYMBOLIC then
    ref.type = GIT_REFERENCE_TYPE.SYMBOLIC
  else
    ref.type = GIT_REFERENCE_TYPE.ALL
  end

  return ref
end


-- =======================
-- | Reference funcionts |
-- =======================


function Reference.__tostring(ref)
  return string.format("Git Ref (%s): %s", GIT_REFERENCE_TYPE_STR[ref.type], ref.name)
end


--- Transforms the reference name into a name "human-readable" version.
---@param ref Reference
---@return string # Shorthand for ref
function Reference.shorthand(ref)
  local c_name = libgit2.git_reference_shorthand(ref.ref[0])
  return ffi.string(c_name)
end


-- ========================
-- | Repository funcionts |
-- ========================


function Repository.__tostring(repo)
  return string.format("Git Repository: %s", repo.path)
end


--- Creates Git repository
---@param path string Path to repository
---@return Repository?
function Repository.open (path)
  local git_repo = ffi.new("struct git_repository*[1]")

  local ret = libgit2.git_repository_open(git_repo, path)
  if ret ~= 0 then
    return nil
  end

  ffi.gc(git_repo, function (repo)
    libgit2.git_repository_free(repo[0])
  end)

  return Repository.new(git_repo)
end


--- Checks a Repository is empty or not
---@param repo Repository input repository
---@return boolean is_empty Whether this git repo is empty
function Repository.is_empty (repo)
  local ret = libgit2.git_repository_is_empty(repo.repo[0])
  if ret == 1 then
    return true
  elseif ret == 0 then
    return false
  else
    error("Repository is corrupted")
  end
end


--- Checks a Repository is bare or not
---@param repo Repository input repository
---@return boolean is_bare Whether this git repo is bare repository
function Repository.is_bare(repo)
  local ret = libgit2.git_repository_is_bare(repo.repo[0])
  return ret == 1
end


--- Checks a Repository HEAD is detached or not
---@param repo Repository input repository
---@return boolean is_head_detached Whether this git repo head detached
function Repository.is_head_detached(repo)
  local ret = libgit2.git_repository_head_detached(repo.repo[0])
  return ret == 1
end


--- Retrieves reference pointed at by HEAD.
---@param repo Repository input repository
---@return Reference?
function Repository.head(repo)
  local c_ref = ffi.new("struct git_reference*[1]")

  local ret = libgit2.git_repository_head(c_ref, repo.repo[0])
  if ret == libgit2.GIT_EUNBORNBRANCH or ret == libgit2.GIT_ENOTFOUND then
    return nil
  elseif ret ~= 0 then
    error("Failed to get head")
  end

  ffi.gc(c_ref, function (ref)
    libgit2.git_reference_free(ref[0])
  end)

  return Reference.new(c_ref)
end

-- ==================
-- | Git2Module     |
-- ==================

---@class Git2Module
local M = {}

M.Repository = Repository
M.Reference = Reference

---@enum REFERENCE_NAMESPACE
M.REFERENCE_NAMESPACE = GIT_REFERENCE_NAMESPACE


---@enum REFERENCE_TYPE
M.REFERENCE_TYPE = GIT_REFERENCE_TYPE


function M.destroy()
  libgit2_init_count = libgit2.git_libgit2_shutdown()
end

---Get Git status
---@return string
function M.status()
  return "hello git_repo "
end

return M
