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

local GIT_DELTA_STRING = {
  "UNMODIFIED",
  "ADDED",
  "DELETED",
  "MODIFIED",
  "RENAMED",
  "COPIED",
  "IGNORED",
  "UNTRACKED",
  "TYPECHANGE",
  "UNREADABLE",
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

---@class GitRemote
---@field remote ffi.cdata* libgit2 struct git_remote*[1]
---@field name string
---@field url string
local Remote = {}
Remote.__index = Remote

---@class GitRevisionWalker
---@field repo ffi.cdata* libgit2 struct git_repository*
---@field revwalk ffi.cdata* libgit2 struct git_revwalk*[1]
local RevisionWalker = {}
RevisionWalker.__index = RevisionWalker

---@class GitSignature
---@field sign ffi.cdata* libgit2 git_signature*[1]
local Signature = {}
Signature.__index = Signature

---@class GitPatch
---@field patch ffi.cdata* libgit2 git_patch*[1]
local Patch = {}
Patch.__index = Patch

---@class GitDiff
---@field diff ffi.cdata* libgit2 git_diff*[1]
local Diff = {}
Diff.__index = Diff

---@class GitDiffHunk
---@field num_lines integer
---@field old_start integer
---@field old_lines integer
---@field new_start integer
---@field new_lines integer
---@field header string
local DiffHunk = {}

---@class GitDiffLine
---@field origin string
---@field old_lineno integer
---@field new_lineno integer
---@field num_lines integer
---@field content string

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

---@param oid ffi.cdata* libgit2 git_oid*
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

  local c_buf = libgit2.char_array(n+1)
  libgit2.C.git_oid_tostr(c_buf, n+1, self.oid)
  return ffi.string(c_buf)
end


---@param oid_str string hex formatted object id.
---@return boolean
function ObjectId:streq(oid_str)
  return (libgit2.C.git_oid_streq(self.oid, oid_str) == 0)
end


---@return string
function ObjectId:__tostring()
  return self:tostring(8)
end


---@param a GitObjectId
---@param b GitObjectId
---@return boolean
function ObjectId.__eq(a, b)
   return (libgit2.C.git_oid_equal(a.oid, b.oid) ~= 0)
end


-- ====================
-- | Commit functions |
-- ====================


-- Init GitCommit.
---@param git_commit ffi.cdata* libgit2 git_commit*[1], this owns the data.
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


-- Gets the id of a commit.
---@return GitObjectId
function Commit:id()
  local git_oid = libgit2.C.git_commit_id(self.commit[0])
  return ObjectId.new(git_oid)
end


-- Gets GitCommit messages.
---@return string
function Commit:message()
  local c_char = libgit2.C.git_commit_message(self.commit[0])
  return vim.trim(ffi.string(c_char))
end


---@return string
function Commit:author()
  local sig = libgit2.C.git_commit_author(self.commit[0])
  return ffi.string(sig.name)
end


-- Gets the number of parents of this commit
---@return integer parentcount
function Commit:nparents()
  return libgit2.C.git_commit_parentcount(self.commit[0])
end

-- Gets the specified parent of the commit.
---@param i integer Parent index (0-based)
---@return GitCommit?
---@return GIT_ERROR
function Commit:parent(i)
  local c_commit = libgit2.git_commit_double_pointer()
  local err = libgit2.C.git_commit_parent(c_commit, self.commit[0], i)
  if err ~= 0 then
    return nil, err
  end

  return Commit.new(c_commit), 0
end


-- Gets the oids of a all parents
---@return GitObjectId[]
function Commit:parent_oids()
  local parents = {}
  local nparents = self:nparents()
  if nparents < 1 then
    return parents
  end

  local i = 0
  while i < nparents do
    local oid = libgit2.C.git_commit_parent_id(self.commit[0], i);
    parents[i+1] = ObjectId.new(oid)
    i = i + 1
  end

  return parents
end


-- =======================
-- | Reference functions |
-- =======================

---Creates new Reference object
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

    local err = libgit2.C.git_reference_resolve(resolved, self.ref[0])
    if err ~= 0 then
      return nil, err
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
  local c_object = libgit2.git_object_double_pointer()

  local err = libgit2.C.git_reference_peel(c_object, self.ref[0], type);
  if err ~= 0 then
    return nil, err
  end

  return Object.new(c_object), 0
end


-- Recursively peel reference until commit object is found.
---@return GitCommit?
---@return GIT_ERROR err Error code
function Reference:peel_commit()
  local c_object = libgit2.git_object_double_pointer()

  local err = libgit2.C.git_reference_peel(c_object, self.ref[0], libgit2.GIT_OBJECT.COMMIT);
  if err ~= 0 then
    return nil, err
  end

  local c_commit = libgit2.git_commit_double_pointer()
  c_commit[0] = ffi.cast(libgit2.git_commit_pointer, c_object[0])

  return Commit.new(c_commit), 0
end


-- Gets upstream for a branch.
---@return GitReference? Reference git upstream reference
---@return GIT_ERROR
function Reference:branch_upstream()
  if self.namespace ~= GIT_REFERENCE_NAMESPACE.BRANCH then
    return nil, 0
  end

  local c_ref = libgit2.git_reference_double_pointer()

  local err = libgit2.C.git_branch_upstream(c_ref, self.ref[0]);

  if err ~= 0 then
    return nil, err
  end

  return Reference.new(c_ref), 0
end


-- Retrieves the upstream remote name of a local branch / upstream.
---@return string?
function Reference:remote_name()
  if self.namespace == GIT_REFERENCE_NAMESPACE.REMOTE then
    return self.name:match("remotes/([^/]+)/", 6)
  end
end

-- ============================
-- | RevisionWalker functions |
-- ============================


-- Inits new GitRevisionWalker object.
---@param repo ffi.cdata* struct git_respository*, don't own data
---@param revwalk ffi.cdata* struct git_revwalk*[1], own cdata
---@return GitRevisionWalker
function RevisionWalker.new(repo, revwalk)
  local git_walker = {
    repo = libgit2.git_repository_pointer(repo),
    revwalk = revwalk
  }
  setmetatable(git_walker, RevisionWalker)

  ffi.gc(git_walker.revwalk, function(ptr)
    libgit2.C.git_revwalk_free(ptr[0])
  end)

  return git_walker
end

---@return GIT_ERROR
function RevisionWalker:reset()
  return libgit2.C.git_revwalk_reset(self.revwalk[0])
end

---@param topo boolean sort in topo order
---@param time boolean sort by time
---@param reverse boolean reverse
---@return GIT_ERROR
function RevisionWalker:sort(topo, time, reverse)
  if not (topo or time or reverse) then
    return 0
  end

  local mode = 0ULL
  if topo then
    mode = bit.bor(mode, libgit2.GIT_SORT.TOPOLOGICAL)
  end
  if time then
    mode = bit.bor(mode, libgit2.GIT_SORT.TIME)
  end
  if reverse then
    mode = bit.bor(mode, libgit2.GIT_SORT.REVERSE)
  end

  return libgit2.C.git_revwalk_sorting(self.revwalk[0], mode);
end


---@param oid GitObjectId
---@return GIT_ERROR
function RevisionWalker:push(oid)
  return libgit2.C.git_revwalk_push(self.revwalk[0], oid.oid)
end


---@return GIT_ERROR
function RevisionWalker:push_head()
  return libgit2.C.git_revwalk_push_head(self.revwalk[0])
end


-- Push matching references
---@param glob string
---@return GIT_ERROR
function RevisionWalker:push_glob(glob)
  return libgit2.C.git_revwalk_push_glob(self.revwalk[0], glob)
end


-- Push the OID pointed to by a reference
---@param refname string
---@return GIT_ERROR
function RevisionWalker:push_ref(refname)
  return libgit2.C.git_revwalk_push_ref(self.revwalk[0], refname)
end


---@param oid GitObjectId
---@return GIT_ERROR
function RevisionWalker:hide(oid)
  return libgit2.C.git_revwalk_hide(self.revwalk[0], oid.oid)
end


---@return fun(): GitObjectId?, GitCommit?
function RevisionWalker:iter()
  local git_oid = libgit2.git_oid()

  return function()
    local err = libgit2.C.git_revwalk_next(git_oid, self.revwalk[0])
    if err ~= 0 then
      return nil, nil
    end

    local c_commit = libgit2.git_commit_double_pointer()
    err = libgit2.C.git_commit_lookup(c_commit, self.repo, git_oid)
    if err ~= 0 then
      return nil, nil
    end

    return ObjectId.new(git_oid), Commit.new(c_commit)
  end
end


-- ====================
-- | Remote functions |
-- ====================


-- Inits new GitRemote object.
---@param remote ffi.cdata* struct git_remote*[1], own data
---@return GitRemote
function Remote.new(remote)
  local git_remote = { remote = remote  }
  setmetatable(git_remote, Remote)

  git_remote.name = ffi.string(libgit2.C.git_remote_name(remote[0]))
  git_remote.url = ffi.string(libgit2.C.git_remote_url(remote[0]))

  ffi.gc(git_remote.remote, function(c_remote)
    libgit2.C.git_remote_free(c_remote[0])
  end)

  return git_remote
end


-- =======================
-- | Signature functions |
-- =======================


---@param signature ffi.cdata* libgit2 git_signature*[1], own data
function Signature.new(signature)
  local git_signature = { sign = signature }
  setmetatable(git_signature, Signature)

  ffi.gc(git_signature.sign, function(ptr)
    libgit2.C.git_signature_free(ptr[0])
  end)
  return git_signature
end


---@return string
function Signature:name()
  return ffi.string(self.sign[0].name)
end


---@return string
function Signature:email()
  return ffi.string(self.sign[0].email)
end


function Signature:__tostring()
  return string.format("%s <%s>", self:name(), self:email())
end


-- ===================
-- | Index functions |
-- ===================


-- Inits new GitIndex object.
---@param index ffi.cdata* struct git_index*[1], own cdata
---@return GitIndex
function Index.new(index)
  local git_index = { index = index }
  setmetatable(git_index, Index)

  ffi.gc(git_index.index, function (c_index)
    libgit2.C.git_index_free(c_index[0])
  end)

  return git_index
end


-- Gets the count of entries currently in the index
---@return integer
function Index:nentry()
  local entrycount = libgit2.C.git_index_entrycount(self.index[0])
  return math.floor(tonumber(entrycount) or -1)
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


-- Write the index as a tree
---@return GitObjectId?
---@return GIT_ERROR
function Index:write_tree()
  local tree_oid = libgit2.git_oid()
  local err = libgit2.C.git_index_write_tree(tree_oid, self.index[0]);
  if err ~= 0 then
    return nil, err
  end
  return ObjectId.new(tree_oid), 0
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


-- Determine if the index contains entries representing file conflicts.
---@return boolean has_conflicts
function Index:has_conflicts()
  return (libgit2.C.git_index_has_conflicts(self.index[0]) > 0)
end

-- ==================
-- | Diff functions |
-- ==================

---Create new GitDiff object
---@param diff ffi.cdata* libgit2 struct git_diff*[1], own cdata
---@return GitDiff
function Diff.new(diff)
  local git_diff = { diff = diff }
  setmetatable(git_diff, Diff)

  ffi.gc(git_diff.diff, function(ptr)
    libgit2.C.git_diff_free(ptr[0])
  end)

  return git_diff
end

---@parm diff_str string
---@return GitDiff?
---@return GIT_ERROR
function Diff.from_buffer(diff_str)
  local diff = libgit2.git_diff_double_pointer()

  local err = libgit2.C.git_diff_from_buffer(diff, diff_str, diff_str:len())
  if err ~= 0 then
    return nil, err
  end

  return Diff.new(diff), 0
end

---@param format GIT_DIFF_FORMAT
---@return string
function Diff:tostring(format)
  local buf = libgit2.git_buf()
  local err = libgit2.C.git_diff_to_buf(buf, self.diff[0], format)
  if err ~= 0 then
    libgit2.C.git_buf_dispose(buf)
    return ""
  end

  local diff = ffi.string(buf[0].ptr, buf[0].size)
  libgit2.C.git_buf_dispose(buf)
  return diff
end

function Diff:__tostring()
  return self:tostring(libgit2.GIT_DIFF_FORMAT.PATCH)
end

---Gets accumulate diff statistics for all patches.
---@return GitDiffStats?
---@return GIT_ERROR
function Diff:stats()
  local diff_stats = libgit2.git_diff_stats_double_pointer()
  local err = libgit2.C.git_diff_get_stats(diff_stats, self.diff[0]);
  if err ~= 0 then
    return nil, err
  end
  ---@type GitDiffStats
  local stats = {
    changed = libgit2.C.git_diff_stats_files_changed(diff_stats[0]),
    insertions = libgit2.C.git_diff_stats_insertions(diff_stats[0]),
    deletions = libgit2.C.git_diff_stats_deletions(diff_stats[0])
  }

  libgit2.C.git_diff_stats_free(diff_stats[0]);
  return stats, 0
end

---Gets patches from diff as a list
---@param sort_case_sensitive boolean
---@return GitDiffPatchItem[]
---@return GIT_ERROR
function Diff:patches(sort_case_sensitive)
  local patches = {}
  local err = 0

  local num_deltas = tonumber(libgit2.C.git_diff_num_deltas(self.diff[0]))
  for i=0,num_deltas-1 do
    local delta = libgit2.C.git_diff_get_delta(self.diff[0], i)

    local c_patch = libgit2.git_patch_double_pointer()
    err = libgit2.C.git_patch_from_diff(c_patch, self.diff[0], i)
    if err ~= 0 then
      break
    end

    local patch = Patch.new(c_patch)

    ---@type GitDiffPatchItem
    local patch_item = {
      status    = delta.status,
      path      = ffi.string(delta.old_file.path),
      new_path  = ffi.string(delta.new_file.path),
      num_hunks = tonumber(patch:nhunks()) or -1,
      patch     = patch
    }

    table.insert(patches, patch_item)
  end

  if #patches > 0 and sort_case_sensitive then
    -- sort patches by name
    table.sort(patches, function (a, b)
      return a.path < b.path
    end)
  end

  return patches, err
end


-- ===================
-- | Patch functions |
-- ===================

---Creates new GitPatch object
---@param patch ffi.cdata* libgit2 struct git_patch*[1], own cdata
---@return GitPatch
function Patch.new(patch)
  local git_patch = { patch = patch }
  setmetatable(git_patch, Patch)

  ffi.gc(git_patch.patch, function (ptr)
    libgit2.C.git_patch_free(ptr[0])
  end)

  return git_patch
end

---Gets the content of a patch as a single diff text.
---@return string
function Patch:__tostring()
  local buf = libgit2.git_buf()
  local err = libgit2.C.git_patch_to_buf(buf, self.patch[0])
  if err ~= 0 then
    libgit2.C.git_buf_dispose(buf)
    return ""
  end

  local patch = ffi.string(buf[0].ptr, buf[0].size)
  libgit2.C.git_buf_dispose(buf)
  return patch
end

---@return GitDiffStats?
---@return GIT_ERROR
function Patch:stats()
  local number = libgit2.size_t_array(2)
  local err = libgit2.C.git_patch_line_stats(
    nil, number, number + 1, self.patch[0]
  )
  if err ~= 0 then
    return nil, err
  end

  return {
    changed = 1,
    insertions = tonumber(number[0]),
    deletions = tonumber(number[1])
  }, 0
end

---Gets the number of hunks in a patch
---@return integer
function Patch:nhunks()
  return libgit2.C.git_patch_num_hunks(self.patch[0])
end

---@param idx integer Hunk index 0-based
---@return GitDiffHunk?
---@return GIT_ERROR
function Patch:hunk(idx)
  local num_lines = libgit2.size_t_array(1)
  local hunk = libgit2.git_diff_hunk_double_pointer()

  local err = libgit2.C.git_patch_get_hunk(
    hunk, num_lines, self.patch[0], idx
  )
  if err ~= 0 then
    return nil, err
  end

  ---@type GitDiffHunk
  local diff_hunk = {
    num_lines = num_lines[0],
    old_start = hunk[0].old_start,
    old_lines = hunk[0].old_lines,
    new_start = hunk[0].new_start,
    new_lines = hunk[0].new_lines,
    header    = ffi.string(hunk[0].header, hunk[0].header_len)
  }

  return diff_hunk, 0
end

---@param hunk_idx integer Hunk index 0-based
---@param line_idx integer Line index in hunk, 0-based
---@return GitDiffLine?
---@return GIT_ERROR
function Patch:hunk_line(hunk_idx, line_idx)
  local diff_line = libgit2.git_diff_line_double_pointer()

  local err = libgit2.C.git_patch_get_line_in_hunk(diff_line, self.patch[0], hunk_idx, line_idx)
  if err ~= 0 then
    return nil, err
  end

  ---@type GitDiffLine
  local ret = {
    origin     = string.char(diff_line[0].origin),
    old_lineno = diff_line[0].old_lineno,
    new_lineno = diff_line[0].new_lineno,
    num_lines  = diff_line[0].num_lines,
    content    = ffi.string(diff_line[0].content, diff_line[0].content_len)
  }
  return ret, 0
end

---Gets the number of lines in a hunk.
---@param i integer
---@return integer
function Patch:hunk_num_lines(i)
  return libgit2.C.git_patch_num_lines_in_hunk(self.patch[0], i)
end


-- ========================
-- | Repository functions |
-- ========================

---@class GitStatusItem
---@field path string File path
---@field new_path string? New file path in case of rename
---@field worktree_status GIT_DELTA Git status in worktree to index
---@field index_status GIT_DELTA Git status in index to head
---@field renamed boolean Extra flag to indicate whether item is renamed

---@class GitStatusUpstream
---@field name string
---@field oid string
---@field message string
---@field author string
---@field ahead integer
---@field behind integer
---@field remote string
---@field remote_url string

---@class GitStatusHead
---@field name string
---@field oid string
---@field message string
---@field author string
---@field is_detached boolean
---@field namespace GIT_REFERENCE_NAMESPACE

---@class GitStatusResult
---@field head GitStatusHead
---@field upstream GitStatusUpstream?
---@field status GitStatusItem[]


---@class GitBranch
---@field name string
---@field shorthand string
---@field type GIT_BRANCH


---@alias GitDiffStats {changed: integer, insertions: integer, deletions: integer} Diff stats

---@alias GitDiffPatchItem {status: GIT_DELTA, path: string, new_path:string, num_hunks: integer, patch: GitPatch}


local DEFAULT_STATUS_FLAGS = bit.bor(
  libgit2.GIT_STATUS_OPT.INCLUDE_UNTRACKED,
  libgit2.GIT_STATUS_OPT.RENAMES_HEAD_TO_INDEX,
  libgit2.GIT_STATUS_OPT.RENAMES_INDEX_TO_WORKDIR,
  libgit2.GIT_STATUS_OPT.RECURSE_UNTRACKED_DIRS,
  libgit2.GIT_STATUS_OPT.SORT_CASE_SENSITIVELY
)

function Repository:__tostring()
  return string.format("Git Repository: %s", self.path)
end

---Opens Git repository
---@param path string Path to repository
---@param search boolean Whether to search parent directories.
---@return GitRepository?
---@return GIT_ERROR
function Repository.open (path, search)
  local git_repo = libgit2.git_repository_double_pointer()

  local open_flag = 0ULL
  if not search then
    open_flag = bit.bor(open_flag, libgit2.GIT_REPOSITORY_OPEN.NO_SEARCH)
  end

  local err = libgit2.C.git_repository_open_ext(git_repo, path, open_flag, nil)
  if err ~= 0 then
    return nil, err
  end

  return Repository.new(git_repo), 0
end

---Checks a Repository is empty or not
---@return boolean is_empty Whether this git repo is empty
function Repository:is_empty()
  local ret = libgit2.C.git_repository_is_empty(self.repo[0])
  if ret == 1 then
    return true
  elseif ret == 0 then
    return false
  else
    error("Repository is corrupted, code" .. ret)
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


-- Get the path of this repository
function Repository:repo_path()
  return ffi.string(libgit2.C.git_repository_path(self.repo[0]))
end


-- Retrieves reference pointed at by HEAD.
---@return GitReference?
---@return GIT_ERROR
function Repository:head()
  local c_ref = libgit2.git_reference_double_pointer()

  local err = libgit2.C.git_repository_head(c_ref, self.repo[0])
  if err ~= 0 then
    return nil, err
  end

  return Reference.new(c_ref), 0
end


-- Listings branches of a repo.
---@param locals boolean Includes local branches.
---@param remotes boolean Include remote branches.
---@return GitBranch[]?
---@return GIT_ERROR
function Repository:branches(locals, remotes)
  if not locals and not remotes then
    return {}, 0
  end

  local branch_flags = 0
  if locals then
    branch_flags = libgit2.GIT_BRANCH.LOCAL
  end
  if remotes then
    branch_flags = bit.bor(branch_flags, libgit2.GIT_BRANCH.REMOTE)
  end

  local c_branch_iter = libgit2.git_branch_iterator_double_pointer()
  local err = libgit2.C.git_branch_iterator_new(c_branch_iter, self.repo[0], branch_flags)
  if err ~= 0 then
    return nil, err
  end

  ---@type GitBranch[]
  local branches = {}
  local c_ref = libgit2.git_reference_double_pointer()
  local c_branch_type = libgit2.unsigned_int_array(1)
  while libgit2.C.git_branch_next(c_ref, c_branch_type, c_branch_iter[0]) == 0 do
    ---@type GitBranch
    local br = {
      name = ffi.string(libgit2.C.git_reference_name(c_ref[0])),
      shorthand = ffi.string(libgit2.C.git_reference_shorthand(c_ref[0])),
      type = math.floor(tonumber(c_branch_type[0]) or 0)
    }
    table.insert(branches, br)

    libgit2.C.git_reference_free(c_ref[0])
  end

  libgit2.C.git_branch_iterator_free(c_branch_iter[0])

  return branches, 0
end


-- Calculates ahead and behind information.
---@param local_commit GitObjectId The commit which is considered the local or current state.
---@param upstream_commit GitObjectId The commit which is considered upstream.
---@return number? ahead Unique ahead commits.
---@return number? behind Unique behind commits.
---@return GIT_ERROR err Error code.
function Repository:ahead_behind(local_commit, upstream_commit)
  local c_ahead = libgit2.size_t_array(2)

  local err = libgit2.C.git_graph_ahead_behind(
    c_ahead, c_ahead + 1, self.repo[0], local_commit.oid, upstream_commit.oid
  )

  if err ~= 0 then
    return nil, nil, err
  end

  return tonumber(c_ahead[0]), tonumber(c_ahead[1]), 0
end


-- Gets commit from a reference.
---@param oid GitObjectId
---@return GitCommit?
---@return GIT_ERROR
function Repository:commit_lookup (oid)
  local c_commit = libgit2.git_commit_double_pointer()

  local err = libgit2.C.git_commit_lookup(c_commit, self.repo[0], oid.oid)
  if err ~= 0 then
    return nil, err
  end

  return Commit.new(c_commit), 0
end


-- Gets repository index.
---@return GitIndex?
---@return GIT_ERROR
function Repository:index ()
  local c_index = libgit2.git_index_double_pointer()

  local err = libgit2.C.git_repository_index(c_index, self.repo[0])
  if err ~= 0 then
    return nil, err
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
      local c_paths = libgit2.const_char_pointer_array(#paths, paths)
      local strarray = libgit2.git_strarray_readonly()

      -- for i, p in ipairs(paths) do
      --   c_paths[i-1] = p
      -- end

      strarray[0].strings = c_paths
      strarray[0].count = #paths

      return libgit2.C.git_reset_default(self.repo[0], commit.obj[0], strarray);
    end
    return 0
  end
end


-- Finds the remote name of a remote-tracking branch.
---@param ref string Ref name
---@return string? remote Git remote name
---@return GIT_ERROR
function Repository:branch_remote_name(ref)
  local c_buf = libgit2.git_buf()

  local err = libgit2.C.git_branch_remote_name(c_buf, self.repo[0], ref)
  if err ~= 0 then
    libgit2.C.git_buf_dispose(c_buf)
    return nil, err
  end

  local remote = ffi.string(c_buf[0].ptr, c_buf[0].size)
  libgit2.C.git_buf_dispose(c_buf)

  return remote, 0
end


-- Retrieves the upstream remote of a local branch.
---@param ref string Ref name
---@return string? remote Git remote name
---@return GIT_ERROR
function Repository:branch_upstream_remote_name(ref)
  local c_buf = libgit2.git_buf()

  local err = libgit2.C.git_branch_upstream_remote(c_buf, self.repo[0], ref)
  if err ~= 0 then
    libgit2.C.git_buf_dispose(c_buf)
    return nil, err
  end

  local remote = ffi.string(c_buf[0].ptr, c_buf[0].size)
  libgit2.C.git_buf_dispose(c_buf)

  return remote, 0
end


-- Gets the information for a particular remote.
---@param remote string
---@return GitRemote?
---@return GIT_ERROR
function Repository:remote_lookup(remote)
  local c_remote = libgit2.git_remote_double_pointer()

  local err = libgit2.C.git_remote_lookup(c_remote, self.repo[0], remote)
  if err ~= 0 then
    return nil, err
  end

  return Remote.new(c_remote), 0
end


---Reads status of a given file path.
---this can't detect a rename.
---@param path string Git file path.
---@return GIT_DELTA worktree_status Git Status in worktree.
---@return GIT_DELTA index_status Git Status in index.
---@return GIT_ERROR return_code Git return code.
function Repository:status_file(path)
  local worktree_status, index_status = libgit2.GIT_DELTA.UNMODIFIED, libgit2.GIT_DELTA.UNMODIFIED
  local c_status = libgit2.unsigned_int_array(1)

  local err = libgit2.C.git_status_file(c_status, self.repo[0], path)
  if err ~= 0 then
    return worktree_status, index_status, err
  end

  local status = tonumber(c_status[0])
  if status ~= nil then
    if bit.band(status, libgit2.GIT_STATUS.WT_NEW) ~= 0 then
      worktree_status = libgit2.GIT_DELTA.UNTRACKED
      index_status = libgit2.GIT_DELTA.UNTRACKED
    elseif bit.band(status, libgit2.GIT_STATUS.WT_MODIFIED) ~= 0 then
      worktree_status = libgit2.GIT_DELTA.MODIFIED
    elseif bit.band(status, libgit2.GIT_STATUS.WT_DELETED) ~= 0 then
      worktree_status = libgit2.GIT_DELTA.DELETED
    elseif bit.band(status, libgit2.GIT_STATUS.WT_TYPECHANGE) ~= 0 then
      worktree_status = libgit2.GIT_DELTA.TYPECHANGE
    elseif bit.band(status, libgit2.GIT_STATUS.WT_UNREADABLE) ~= 0 then
      worktree_status = libgit2.GIT_DELTA.UNREADABLE
    elseif bit.band(status, libgit2.GIT_STATUS.IGNORED) ~= 0 then
      worktree_status = libgit2.GIT_DELTA.IGNORED
    elseif bit.band(status, libgit2.GIT_STATUS.CONFLICTED) ~= 0 then
      worktree_status = libgit2.GIT_DELTA.CONFLICTED
    end

    if bit.band(status, libgit2.GIT_STATUS.INDEX_NEW) ~= 0 then
      index_status = libgit2.GIT_DELTA.ADDED
    elseif bit.band(status, libgit2.GIT_STATUS.INDEX_MODIFIED) ~= 0 then
      index_status = libgit2.GIT_DELTA.MODIFIED
    elseif bit.band(status, libgit2.GIT_STATUS.INDEX_DELETED) ~= 0 then
      index_status = libgit2.GIT_DELTA.DELETED
    elseif bit.band(status, libgit2.GIT_STATUS.INDEX_TYPECHANGE) ~= 0 then
      index_status = libgit2.GIT_DELTA.TYPECHANGE
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
  local err

  local opts = libgit2.git_status_options(libgit2.GIT_STATUS_OPTIONS_INIT)
  -- libgit2.C.git_status_options_init(opts, libgit2.GIT_STATUS_OPTIONS_VERSION)
  opts[0].show = libgit2.GIT_STATUS_SHOW.INDEX_AND_WORKDIR
  opts[0].flags = DEFAULT_STATUS_FLAGS

  local status = libgit2.git_status_list_double_pointer()
  err = libgit2.C.git_status_list_new(status, self.repo[0], opts)
  if err ~= 0 then
    return nil, err
  end

  -- Get Head information
  local repo_head
  repo_head, err = self:head()
  if repo_head == nil then
    return nil, err
  end

  -- local repo_head_oid, _ = repo_head:target()
  -- if repo_head_oid ~= nil then
  --   repo_head_oid_str = tostring(repo_head_oid)
  --   repo_head_msg = self:commit_lookup(repo_head_oid):message()
  -- end

  local repo_head_commit, _ = repo_head:peel_commit()
  local repo_head_oid = repo_head_commit and repo_head_commit:id() or nil

  ---@type GitStatusResult
  local result = {
    head = {
      name        = repo_head:shorthand(),
      oid         = repo_head_oid and tostring(repo_head_oid) or "",
      author      = repo_head_commit and repo_head_commit:author() or "",
      message     = repo_head_commit and repo_head_commit:message() or "",
      is_detached = self:is_head_detached(),
      namespace   = repo_head.namespace
    },
    status = {}
  }

  -- Get upstream information
  local repo_upstream
  repo_upstream, err = repo_head:branch_upstream()
  if repo_upstream then
    ---@type number
    local ahead, behind = 0, 0
    local commit_local = repo_head_oid
    -- local commit_upstream, _ = repo_upstream:target()
    local commit_upstream, _ = repo_upstream:peel_commit()
    local commit_upstream_oid = commit_upstream and commit_upstream:id() or nil

    if commit_upstream_oid and commit_local then
      local nilable_ahead, nilable_behind, _ = self:ahead_behind(commit_local, commit_upstream_oid)
      if nilable_ahead ~= nil and nilable_behind ~= nil then
        ahead, behind = nilable_ahead, nilable_behind
      end
    end

    local remote_name = repo_upstream:remote_name()
    local remote
    if remote_name then
      remote, _ = self:remote_lookup(remote_name)
    end

    result.upstream = {
      name       = repo_upstream:shorthand(),
      oid        = commit_upstream_oid and tostring(commit_upstream_oid) or "",
      message    = commit_upstream and commit_upstream:message() or "",
      author     = commit_upstream and commit_upstream:author() or "",
      ahead      = ahead,
      behind     = behind,
      remote     = remote and remote.name or "",
      remote_url = remote and remote.url or "",
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
      worktree_status = libgit2.GIT_DELTA.UNMODIFIED,
      index_status    = libgit2.GIT_DELTA.UNMODIFIED,
      renamed         = false,
    }
    ---@type string
    local old_path, new_path

    if entry.index_to_workdir ~= nil then
      old_path = ffi.string(entry.index_to_workdir.old_file.path)
      new_path = ffi.string(entry.index_to_workdir.new_file.path)

      status_item.path = old_path
      status_item.worktree_status = entry.index_to_workdir.status

      if bit.band(entry.status, libgit2.GIT_STATUS.WT_NEW) ~= 0 then
        status_item.worktree_status = libgit2.GIT_DELTA.UNTRACKED
        status_item.index_status = libgit2.GIT_DELTA.UNTRACKED
      end

      if bit.band(entry.status, libgit2.GIT_STATUS.WT_RENAMED) ~= 0 then
        status_item.renamed = true
        status_item.new_path = new_path
      end
    end

    if entry.head_to_index ~= nil then
      old_path = ffi.string(entry.head_to_index.old_file.path)
      new_path = ffi.string(entry.head_to_index.new_file.path)

      status_item.path = old_path
      status_item.index_status = entry.head_to_index.status

      if bit.band(entry.status, libgit2.GIT_STATUS.INDEX_RENAMED) ~= 0 then
        status_item.renamed = true
        status_item.new_path = new_path
      end
    end

    table.insert(result.status, status_item)
    ::git_status_list_continue::
  end

  -- free C resources
  libgit2.C.git_status_list_free(status[0])

  return result, 0
end


---Create a new action signature with default user and now timestamp.
---@return GitSignature?
---@return GIT_ERROR
function Repository:signature_default()
  local git_signature = libgit2.git_signature_double_pointer()

  local err = libgit2.C.git_signature_default(git_signature, self.repo[0]);
  if err ~= 0 then
    return nil, err
  end

  return Signature.new(git_signature), 0
end


---Creates new commit in the repository.
---@param index GitIndex
---@param signature GitSignature
---@param message string
---@return GitObjectId?
---@return GIT_ERROR
function Repository:commit(index, signature, message)
  -- get head as parent commit
  local head, err = self:head()
  if err ~= 0 and err ~= libgit2.GIT_ERROR.GIT_ENOTFOUND then
    return nil, err
  end
  local parent = nil
  if head then
    parent, err = head:peel_commit()
    if err ~= 0 then
      return nil, err
    end
  end

  local tree_id
  tree_id, err = index:write_tree()
  if not tree_id then
    return nil, err
  end

  local tree = libgit2.git_tree_double_pointer()
  err = libgit2.C.git_tree_lookup(tree, self.repo[0], tree_id.oid)
  if err ~= 0 then
    return nil, err
  end

  local git_oid = libgit2.git_oid()
  err = libgit2.C.git_commit_create_v(
    git_oid,
    self.repo[0], "HEAD",
    signature.sign[0], signature.sign[0],
    "UTF-8", message,
    tree[0],
    parent and 1 or 0,
    parent and parent.commit[0] or nil
  )
  libgit2.C.git_tree_free(tree[0])
  if err ~= 0 then
    return nil, err
  end

  return ObjectId.new(git_oid), 0
end


---Rewords HEAD commit.
---@param signature GitSignature
---@param message string
---@return GitObjectId?
---@return GIT_ERROR
function Repository:amend_reword(signature, message)
  return self:amend(nil, signature, message)
end


---Extends new index to HEAD commit.
---@param index GitIndex
---@return GitObjectId?
---@return GIT_ERROR
function Repository:amend_extend(index)
  return self:amend(index, nil, nil)
end

---Amends an existing commit by replacing only non-NULL values.
---@param index GitIndex?
---@param signature GitSignature?
---@param message string?
---@return GitObjectId?
---@return GIT_ERROR
function Repository:amend(index, signature, message)
  -- get head as parent commit
  local head, head_commit, err
  head, err = self:head()
  if not head then
    return nil, err
  end
  head_commit, err = head:peel_commit()
  if not head_commit then
    return nil, err
  end

  if not (index or signature or message) then
    return head_commit:id(), 0
  end

  local tree = nil
  if index then
    local tree_id
    tree_id, err = index:write_tree()
    if not tree_id then
      return nil, err
    end

    tree = libgit2.git_tree_double_pointer()
    err = libgit2.C.git_tree_lookup(tree, self.repo[0], tree_id.oid)
    if err ~= 0 then
      return nil, err
    end
  end

  local sig = signature and signature.sign[0] or nil

  local git_oid = libgit2.git_oid()
  err = libgit2.C.git_commit_amend(
    git_oid,
    head_commit.commit[0],
    "HEAD",
    sig, sig, nil, message,
    tree ~= nil and tree[0] or nil
  )

  if tree ~= nil then
    libgit2.C.git_tree_free(tree[0])
  end

  if err ~= 0 then
    return nil, err
  end

  return ObjectId.new(git_oid), 0
end


---Returns a GitRevisionWalker, cached it for the repo if possible.
---@return GitRevisionWalker?
---@return GIT_ERROR
function Repository:walker()
  local walker = libgit2.git_revwalk_double_pointer()

  local err = libgit2.C.git_revwalk_new(walker, self.repo[0])
  if err ~= 0 then
    return nil, err
  end

  self._walker = RevisionWalker.new(self.repo[0], walker)
  return self._walker, 0
end


---Frees a cached GitRevisionWalker
function Repository:free_walker()
  if self._walker then
    self._walker = nil
  end
end


---Helper function to keep consistency between
---git_status_options and git_diff_options
---@param status_flag GIT_STATUS_OPT
---@return GIT_DIFF diff_flag
---@return GIT_DIFF_FIND find_flag
local function git_status_flags_to_diff_flags(status_flag)
  local diff_flag = libgit2.GIT_DIFF.INCLUDE_TYPECHANGE
  local find_flag = libgit2.GIT_DIFF_FIND.FIND_FOR_UNTRACKED

  if bit.band(status_flag, libgit2.GIT_STATUS_OPT.INCLUDE_UNTRACKED) ~= 0 then
    diff_flag = bit.bor(diff_flag, libgit2.GIT_DIFF.INCLUDE_UNTRACKED)
  end
  if bit.band(status_flag, libgit2.GIT_STATUS_OPT.INCLUDE_IGNORED) ~= 0 then
		diff_flag = bit.bor(diff_flag, libgit2.GIT_DIFF.INCLUDE_IGNORED)
  end
	if bit.band(status_flag, libgit2.GIT_STATUS_OPT.INCLUDE_UNMODIFIED) ~= 0 then
		diff_flag = bit.bor(diff_flag, libgit2.GIT_DIFF.INCLUDE_UNMODIFIED)
  end
	if bit.band(status_flag, libgit2.GIT_STATUS_OPT.RECURSE_UNTRACKED_DIRS) ~= 0 then
		diff_flag = bit.bor(diff_flag,
      libgit2.GIT_DIFF.RECURSE_UNTRACKED_DIRS,
      libgit2.GIT_DIFF.SHOW_UNTRACKED_CONTENT
    )
  end
	if bit.band(status_flag, libgit2.GIT_STATUS_OPT.DISABLE_PATHSPEC_MATCH) ~= 0 then
		diff_flag = bit.bor(diff_flag, libgit2.GIT_DIFF.DISABLE_PATHSPEC_MATCH)
  end
	if bit.band(status_flag, libgit2.GIT_STATUS_OPT.RECURSE_IGNORED_DIRS) ~= 0 then
		diff_flag = bit.bor(diff_flag, libgit2.GIT_DIFF.RECURSE_IGNORED_DIRS)
  end
	if bit.band(status_flag, libgit2.GIT_STATUS_OPT.EXCLUDE_SUBMODULES) ~= 0 then
		diff_flag = bit.bor(diff_flag, libgit2.GIT_DIFF.IGNORE_SUBMODULES)
  end
	if bit.band(status_flag, libgit2.GIT_STATUS_OPT.UPDATE_INDEX) ~= 0 then
		diff_flag = bit.bor(diff_flag, libgit2.GIT_DIFF.UPDATE_INDEX)
  end
	if bit.band(status_flag, libgit2.GIT_STATUS_OPT.INCLUDE_UNREADABLE) ~= 0 then
		diff_flag = bit.bor(diff_flag, libgit2.GIT_DIFF.INCLUDE_UNREADABLE)
  end
	if bit.band(status_flag, libgit2.GIT_STATUS_OPT.INCLUDE_UNREADABLE_AS_UNTRACKED) ~= 0 then
		diff_flag = bit.bor(diff_flag, libgit2.GIT_DIFF.INCLUDE_UNREADABLE_AS_UNTRACKED)
  end

	if bit.band(status_flag, libgit2.GIT_STATUS_OPT.RENAMES_FROM_REWRITES) ~= 0 then
		find_flag = bit.bor(
      find_flag,
      libgit2.GIT_DIFF_FIND.FIND_AND_BREAK_REWRITES,
      libgit2.GIT_DIFF_FIND.FIND_RENAMES_FROM_REWRITES,
      libgit2.GIT_DIFF_FIND.BREAK_REWRITES_FOR_RENAMES_ONLY
    )
  end

  return diff_flag, find_flag
end


---@param index GitIndex? Repository index, can be null
---@param paths string[]? Git paths, can be null
---@param reverse? boolean whether to reverse the diff
---@return GitDiff?
---@return GIT_ERROR
function Repository:diff_index_to_workdir(index, paths, reverse)
  return self:diff_helper(true, true, index, paths, reverse)
end

---@param index GitIndex? Repository index, can be null
---@param paths string[]? Git paths, can be null
---@param reverse? boolean whether to reverse the diff
---@return GitDiff?
---@return GIT_ERROR
function Repository:diff_head_to_index(index, paths, reverse)
  return self:diff_helper(false, true, index, paths, reverse)
end


---@param index GitIndex? Repository index, can be null
---@param paths string[]? Git paths, can be null
---@param reverse? boolean whether to reverse the diff
---@return GitDiff?
---@return GIT_ERROR
function Repository:diff_head_to_workdir(index, paths, reverse)
  return self:diff_helper(true, false, index, paths, reverse)
end

---@param include_workdir boolean Whether to do include workd_dir in diff target
---@param include_index boolean Wheter to include index in diff target
---@param index GitIndex? Repository index, can be null
---@param paths string[]? Git paths, can be null
---@param reverse boolean? Reverse diff
---@return GitDiff?
---@return GIT_ERROR
function Repository:diff_helper(include_workdir, include_index, index, paths, reverse)
  local c_paths, err
  local opts = libgit2.git_diff_options(libgit2.GIT_DIFF_OPTIONS_INIT)
  local find_opts = libgit2.git_diff_find_options(libgit2.GIT_DIFF_FIND_OPTIONS_INIT)
  local diff = libgit2.git_diff_double_pointer()

  opts[0].id_abbrev = 8
  opts[0].flags, find_opts[0].flags = git_status_flags_to_diff_flags(DEFAULT_STATUS_FLAGS)

  if reverse then
    opts[0].flags = bit.bor(opts[0].flags, libgit2.GIT_DIFF.REVERSE)
  end

  if paths and #paths > 0 then
    c_paths = libgit2.const_char_pointer_array(#paths, paths)
    opts[0].pathspec.strings = c_paths
    opts[0].pathspec.count = #paths
  end

  if include_workdir and include_index then
    -- diff workdir to index
    err = libgit2.C.git_diff_index_to_workdir(
      diff, self.repo[0], index and index.index[0] or nil, opts
    )
  elseif include_workdir or include_index then
    -- diff workd_dir to head or index to head

    local head, head_tree
    head, err = self:head()
    -- if there is no HEAD, that's okay - we'll make an empty iterator
    if err ~= 0 and err ~= libgit2.GIT_ERROR.GIT_ENOTFOUND and err ~= libgit2.GIT_ERROR.GIT_EUNBORNBRANCH then
      return nil, err
    end
    if head then
      head_tree, err = head:peel(libgit2.GIT_OBJECT.TREE)
      if err ~= 0 then
        return nil, err
      end
    end

    if include_index then
      -- diff index to head
      err = libgit2.C.git_diff_tree_to_index(
        diff, self.repo[0],
        head_tree and ffi.cast(libgit2.git_tree_pointer, head_tree.obj[0]) or nil,
        index and index.index[0] or nil, opts
      )
    else
      -- diff workd_dir to head
      err = libgit2.C.git_diff_tree_to_workdir(
        diff, self.repo[0],
        head_tree and ffi.cast(libgit2.git_tree_pointer, head_tree.obj[0]) or nil,
        opts
      )
    end
  else
    return nil, 0
  end

  if err ~= 0 then
    return nil, err
  end

  -- call this to detect rename
  if include_workdir and bit.band(DEFAULT_STATUS_FLAGS, libgit2.GIT_STATUS.WT_RENAMED) ~= 0
    or (include_index and bit.band(DEFAULT_STATUS_FLAGS, libgit2.GIT_STATUS.INDEX_RENAMED) ~= 0)
  then
    err = libgit2.C.git_diff_find_similar(diff[0], find_opts)
    if err ~= 0 then
      libgit2.C.git_diff_free(diff[0])
      return nil, err
    end
  end

  return Diff.new(diff), 0
end

---Applies a diff into workdir
---@param diff GitDiff
---@return GIT_ERROR
function Repository:apply_workdir(diff)
  return self:apply(diff, true, false)
end

---Applies a diff into index
---@param diff GitDiff
---@return GIT_ERROR
function Repository:apply_index(diff)
  return self:apply(diff, false, true)
end

---Applies a diff into index and workdir
---@param diff GitDiff
---@return GIT_ERROR
function Repository:apply_workdir_index(diff)
  return self:apply(diff, true, true)
end

---Applies a diff into workdir or index
---@param diff GitDiff
---@param workdir boolean Apply to workdir
---@param index boolean Apply to index
---@return GIT_ERROR
function Repository:apply(diff, workdir, index)
  if not (workdir or index) then
    return 0
  end

  local opts = libgit2.git_apply_options(libgit2.GIT_APPLY_OPTIONS_INIT)
  local location = 0
  if workdir then
    location = bit.bor(location, libgit2.GIT_APPLY_LOCATION.WORKDIR)
  end
  if index then
    location = bit.bor(location, libgit2.GIT_APPLY_LOCATION.INDEX)
  end

  return libgit2.C.git_apply(self.repo[0], diff.diff[0], location, opts)
end

-- ===================
-- | Utils functions |
-- ===================


---@param delta GIT_DELTA
---@return string char Git status char such as M, A, D.
local function status_char(delta)
  local c = libgit2.C.git_diff_status_char(delta);
  return string.char(c)
end


---Same as status_char but replace " " by "-"
---@param delta GIT_DELTA
---@return string Git status char such as M, A, D.
local function status_char_dash(delta)
  local c = libgit2.C.git_diff_status_char(delta);
  if c == 32 then
    return "-"
  end
  return string.char(c)
end


---@param delta GIT_DELTA
---@return string status status full string such as "UNTRACKED"
local function status_string(delta)
  return GIT_DELTA_STRING[delta+1]
end


---Prettifiy git message
---@param msg string
local function message_prettify(msg)
  local c_buf = libgit2.git_buf()

  local err = libgit2.C.git_buf_grow(c_buf, msg:len() + 1)
  if err ~= 0 then
    return nil, err
  end

  err = libgit2.C.git_message_prettify(c_buf, msg, 1, string.byte("#"))
  if err ~= 0 then
    libgit2.C.git_buf_dispose(c_buf)
    return nil, err
  end

  local prettified = ffi.string(c_buf[0].ptr, c_buf[0].size)
  libgit2.C.git_buf_dispose(c_buf)

  return prettified, 0
end


-- ==================
-- | Git2Module     |
-- ==================

---@class Git2Module
local M = {}

M.Diff = Diff
M.Repository = Repository
M.Reference = Reference


M.GIT_BRANCH = libgit2.GIT_BRANCH
M.GIT_DELTA = libgit2.GIT_DELTA
M.GIT_REFERENCE = libgit2.GIT_REFERENCE
M.GIT_REFERENCE_NAMESPACE = GIT_REFERENCE_NAMESPACE


M.head = Repository.head
M.status = Repository.status
M.status_char = status_char
M.status_char_dash = status_char_dash
M.status_string = status_string
M.message_prettify = message_prettify


function M.destroy()
  libgit2_init_count = libgit2.C.git_libgit2_shutdown()
end


return M
