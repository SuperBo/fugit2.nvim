local ffi = require "ffi"

-- =====================
-- | Libgit2 C section |
-- =====================

--- Load libgit2 via ffi
ffi.cdef[[
  typedef uint64_t git_object_size_t;

  typedef struct git_commit git_commit;
  typedef struct git_index git_index;
  typedef struct git_index_conflict_iterator git_index_conflict_iterator;
  typedef struct git_index_iterator git_index_iterator;
  typedef struct git_object git_object;
  typedef struct git_reference git_reference;
  typedef struct git_repository git_repository;
  typedef struct git_status_list git_status_list;

  typedef struct {
    char **strings;
    size_t count;
  } git_strarray;


  typedef struct {
    const char **strings;
    size_t count;
  } git_strarray_readonly;

  typedef struct {
	  unsigned char id[20];
  } git_oid;

  typedef struct {
    git_oid            id;
    const char        *path;
    git_object_size_t  size;
    uint32_t           flags;
    uint16_t           mode;
    uint16_t           id_abbrev;
  } git_diff_file;

  typedef struct {
    int           status;
    uint32_t      flags;
    uint16_t      similarity;
    uint16_t      nfiles;
    git_diff_file old_file;
    git_diff_file new_file;
  } git_diff_delta;

  typedef struct {
    unsigned int status;
    git_diff_delta *head_to_index;
    git_diff_delta *index_to_workdir;
  } git_status_entry;

  typedef struct {
	  unsigned int     version;
	  int              show;
	  unsigned int     flags;
	  git_strarray     pathspec;
	  struct git_tree* baseline;
	  uint16_t         rename_threshold;
  } git_status_options;


  int git_libgit2_init();
  int git_libgit2_shutdown();

  void git_strarray_dispose(git_strarray *array);

  char * git_oid_tostr(char *out, size_t n, const git_oid *id);

  void git_object_free(git_object *object);
  const git_oid * git_object_id(const git_object *obj);

  int git_commit_lookup(git_commit **commit, git_repository *repo, const git_oid *id);
  int git_commit_lookup_prefix(git_commit **commit, git_repository *repo, const git_oid *id, size_t len);
  void git_commit_free(git_commit *commit);
  const git_oid * git_commit_id(const git_commit *commit);
  git_repository * git_commit_owner(const git_commit *commit);
  const char * git_commit_message(const git_commit *commit);
  const char * git_commit_message_encoding(const git_commit *commit);
  const char * git_commit_message_raw(const git_commit *commit);

  const char * git_reference_shorthand(const git_reference *ref);
  const char * git_reference_name(const git_reference *ref);
  int git_reference_resolve(git_reference **out, const git_reference *ref);
  void git_reference_free(git_reference *ref);
  int git_reference_type(const git_reference *ref);
  const git_oid * git_reference_target(const git_reference *ref);
  int git_reference_peel(git_object **out, const git_reference *ref, int type);

  int git_branch_upstream(git_reference **out, const git_reference *branch);

  int git_repository_open(git_repository **out, const char *path);
  void git_repository_free(git_repository *repo);
  const char* git_repository_path(const git_repository *repo);
  int git_repository_is_empty(git_repository *repo);
  int git_repository_is_bare(const git_repository *repo);
  int git_repository_head_detached(git_repository *repo);
  int git_repository_head(git_reference **out, git_repository *repo);
  int git_repository_index(git_index **out, git_repository *repo);

  void git_index_free(git_index *index);
  int git_index_read(git_index *index, int force);
  int git_index_write(git_index *index);
  int git_index_add_bypath(git_index *index, const char *path);
  int git_index_remove_bypath(git_index *index, const char *path);
  int git_index_remove_directory(git_index *index, const char *dir, int stage);

  int git_status_list_new(git_status_list **out, git_repository *repo, const git_status_options *opts);
  void git_status_list_free(git_status_list *statuslist);
  int git_status_options_init(git_status_options *opts, unsigned int version);
  size_t git_status_list_entrycount(git_status_list *statuslist);
  const git_status_entry* git_status_byindex(git_status_list *statuslist, size_t idx);
  int git_status_should_ignore(int *ignored, git_repository *repo, const char *path);
  int git_status_file(unsigned int *status_flags, git_repository *repo, const char *path);

  int git_reset_default(git_repository *repo, const git_object *target, const git_strarray_readonly *pathspecs);

  int git_graph_ahead_behind(size_t *ahead, size_t *behind, git_repository *repo, const git_oid *local, const git_oid *upstream);
  int git_graph_descendant_of(git_repository *repo, const git_oid *commit, const git_oid *ancestor);
]]


---@class Libgit2Module
---@field C ffi.namespace*
local M = {
  C = ffi.load "libgit2",
}

---@type ffi.ctype*
M.git_repository_double_pointer = ffi.typeof("struct git_repository*[1]")

---@type ffi.ctype*
M.git_reference_double_pointer  = ffi.typeof("struct git_reference*[1]")

-- ================
-- | libgit2 enum |
-- ================

---@enum GIT_ERROR
M.GIT_ERROR = {
  GIT_OK              =  0, -- No error

  GIT_ERROR           = -1, -- Generic error
  GIT_ENOTFOUND       = -3, -- Requested object could not be found
  GIT_EEXISTS         = -4, -- Object exists preventing operation
  GIT_EAMBIGUOUS      = -5, -- More than one object matches
  GIT_EBUFS           = -6, -- Output buffer too short to hold data
  --[[
  GIT_EUSER is a special error that is never generated by libgit2
  code.  You can return it from a callback (e.g to stop an iteration)
  to know that it was generated by the callback and not by libgit2.
  ]]--
  GIT_EUSER           = -7,

  GIT_EBAREREPO       =  -8, -- Operation not allowed on bare repository
  GIT_EUNBORNBRANCH   =  -9, -- HEAD refers to branch with no commits
  GIT_EUNMERGED       = -10, -- Merge in progress prevented operation
  GIT_ENONFASTFORWARD = -11, -- Reference was not fast-forwardable
  GIT_EINVALIDSPEC    = -12, -- Name/ref spec was not in a valid format
  GIT_ECONFLICT       = -13, -- Checkout conflicts prevented operation
  GIT_ELOCKED         = -14, -- Lock file prevented operation
  GIT_EMODIFIED       = -15, -- Reference value does not match expected
  GIT_EAUTH           = -16, -- Authentication error
  GIT_ECERTIFICATE    = -17, -- Server certificate is invalid
  GIT_EAPPLIED        = -18, -- Patch/merge has already been applied
  GIT_EPEEL           = -19, -- The requested peel operation is not possible
  GIT_EEOF            = -20, -- Unexpected EOF
  GIT_EINVALID        = -21, -- Invalid operation or input
  GIT_EUNCOMMITTED    = -22, -- Uncommitted changes in index prevented operation
  GIT_EDIRECTORY      = -23, -- The operation is not valid for a directory
  GIT_EMERGECONFLICT  = -24, -- A merge conflict exists and cannot continue
  GIT_PASSTHROUGH     = -30, -- A user-configured callback refused to act
  GIT_ITEROVER        = -31, -- Signals end of iteration with iterator
  GIT_RETRY           = -32, -- Internal only
  GIT_EMISMATCH       = -33, -- Hashsum mismatch in object
  GIT_EINDEXDIRTY     = -34, -- Unsaved changes in the index would be overwritten
  GIT_EAPPLYFAIL      = -35, -- Patch application failed
  GIT_EOWNER          = -36, -- The object is not owned by the current user
  GIT_TIMEOUT         = -37	 -- The operation timed out
}

---@enum GIT_REFERENCE
M.GIT_REFERENCE = {
  INVALID  = 0, -- Invalid reference
  DIRECT   = 1, -- A reference that points at an object id
  SYMBOLIC = 2, -- A reference that points at another reference
  ALL      = 3, -- Both GIT_REFERENCE_DIRECT | GIT_REFERENCE_SYMBOLIC
}

---@enum GIT_STATUS
M.GIT_STATUS = {
  CURRENT          = 0,

  INDEX_NEW        = 1,     -- 1u << 0
  INDEX_MODIFIED   = 2,     -- 1u << 1
  INDEX_DELETED    = 4,     -- 1u << 2
  INDEX_RENAMED    = 8,     -- 1u << 3
  INDEX_TYPECHANGE = 16,    -- 1u << 4

  WT_NEW           = 128,   -- 1u << 7
  WT_MODIFIED      = 256,   -- 1u << 8
  WT_DELETED       = 512,   -- 1u << 9
  WT_TYPECHANGE    = 1024,  -- 1u << 10
  WT_RENAMED       = 2048,  -- 1u << 11
  WT_UNREADABLE    = 4096,  -- 1u << 12

  IGNORED          = 16384, -- 1u << 14
  CONFLICTED       = 32768, -- 1u << 15
}

---@enum GIT_STATUS_SHOW
M.GIT_STATUS_SHOW = {
  INDEX_AND_WORKDIR = 0,
	INDEX_ONLY = 1,
	WORKDIR_ONLY = 2
}

---@enum GIT_STATUS_OPT
M.GIT_STATUS_OPT = {
	INCLUDE_UNTRACKED               = 1, -- (1u << 0),
	INCLUDE_IGNORED                 = 2, -- (1u << 1),
	INCLUDE_UNMODIFIED              = 4, -- (1u << 2),
	EXCLUDE_SUBMODULES              = 8, -- (1u << 3),
	RECURSE_UNTRACKED_DIRS          = 16, -- (1u << 4),
	DISABLE_PATHSPEC_MATCH          = 32, -- (1u << 5),
	RECURSE_IGNORED_DIRS            = 64, -- (1u << 6),
	RENAMES_HEAD_TO_INDEX           = 128, -- (1u << 7),
	RENAMES_INDEX_TO_WORKDIR        = 256, -- (1u << 8),
	SORT_CASE_SENSITIVELY           = 512, -- (1u << 9),
	SORT_CASE_INSENSITIVELY         = 1024, -- (1u << 10),
	RENAMES_FROM_REWRITES           = 2048, -- (1u << 11),
	NO_REFRESH                      = 4096, -- (1u << 12),
	UPDATE_INDEX                    = 8192, -- (1u << 13),
	INCLUDE_UNREADABLE              = 16384, -- (1u << 14),
	INCLUDE_UNREADABLE_AS_UNTRACKED = 32768, --(1u << 15)
}


---@enum GIT_OBJECT
M.GIT_OBJECT = {
	ANY       = -2, -- Object can be any of the following.
	INVALID   = -1, -- Object is invalid.
	COMMIT    = 1, -- A commit object.
	TREE      = 2, -- A tree (directory listing) object.
	BLOB      = 3, -- A file revision object.
	TAG       = 4, -- An annotated tag object.
	OFS_DELTA = 6, -- A delta, base is given by an offset.
	REF_DELTA = 7  -- A delta, base is given by object id.
}


return M
