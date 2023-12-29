local ffi = require "ffi"

-- =====================
-- | Libgit2 C section |
-- =====================

--- Load libgit2 via ffi
ffi.cdef[[
  typedef uint64_t git_object_size_t;
  typedef int64_t git_off_t;
  typedef int64_t git_time_t;

  typedef struct git_blob git_blob;
  typedef struct git_branch_iterator git_branch_iterator;
  typedef struct git_commit git_commit;
  typedef struct git_config git_config;
  typedef struct git_config_iterator git_config_iterator;
  typedef struct git_diff git_diff;
  typedef struct git_diff_stats git_diff_stats;
  typedef struct git_index git_index;
  typedef struct git_index_conflict_iterator git_index_conflict_iterator;
  typedef struct git_index_iterator git_index_iterator;
  typedef struct git_object git_object;
  typedef struct git_patch git_patch;
  typedef struct git_reference git_reference;
  typedef struct git_remote git_remote;
  typedef struct git_repository git_repository;
  typedef struct git_revwalk git_revwalk;
  typedef struct git_status_list git_status_list;
  typedef struct git_tag git_tag;
  typedef struct git_tree git_tree;
  typedef struct git_tree_entry git_tree_entry;

  typedef struct git_strarray {
    char **strings;
    size_t count;
  } git_strarray;

  typedef struct git_strarray_readonly {
    const char **strings;
    size_t count;
  } git_strarray_readonly;

  typedef struct git_buf {
    char *ptr;
    size_t reserved;
    size_t size;
  } git_buf;

  typedef struct git_oid {
	  unsigned char id[20];
  } git_oid;

  typedef struct git_time {
    git_time_t time;
    int offset;
    char sign;
  } git_time;

  typedef struct git_signature {
    char *name;
    char *email;
    git_time when;
  } git_signature;

  typedef struct git_config_entry {
    const char *name;
    const char *value;
    const char *backend_type;
    const char *origin_path;
    unsigned int include_depth;
    unsigned int level;
    void (*free)(struct git_config_entry *entry);
  } git_config_entry;

  typedef struct git_diff_hunk {
    int    old_start;
    int    old_lines;
    int    new_start;
    int    new_lines;
    size_t header_len;
    char   header[128];
  } git_diff_hunk;

  typedef struct git_diff_line {
    char   origin;
    int    old_lineno;
    int    new_lineno;
    int    num_lines;
    size_t content_len;
    git_off_t content_offset;
    const char *content;
  } git_diff_line;

  typedef struct git_diff_file {
    git_oid            id;
    const char *       path;
    git_object_size_t  size;
    uint32_t           flags;
    uint16_t           mode;
    uint16_t           id_abbrev;
  } git_diff_file;

  typedef struct git_diff_delta {
    int           status;
    uint32_t      flags;
    uint16_t      similarity;
    uint16_t      nfiles;
    git_diff_file old_file;
    git_diff_file new_file;
  } git_diff_delta;

  typedef int (*git_diff_notify_cb)(
    const git_diff *diff_so_far,
    const struct git_diff_delta *delta_to_add,
    const char *matched_pathspec,
	  void *payload
  );

  typedef int (*git_diff_progress_cb)(
    const git_diff *diff_so_far,
    const char *old_path,
    const char *new_path,
    void *payload
  );

  typedef struct git_diff_options {
    unsigned int          version;
    uint32_t              flags;
    unsigned int          ignore_submodules;
    git_strarray_readonly pathspec;
    git_diff_notify_cb    notify_cb;
    git_diff_progress_cb  progress_cb;
    void *                payload;
    uint32_t              context_lines;
    uint32_t              interhunk_lines;
    unsigned int          oid_type;
    uint16_t              id_abbrev;
    int64_t               max_size;
    const char *          old_prefix;
    const char *          new_prefix;
  } git_diff_options ;

  typedef struct git_diff_similarity_metric {
    int (*file_signature)(
      void **out, const git_diff_file *file,
      const char *fullpath, void *payload
    );
    int (*buffer_signature)(
      void **out, const git_diff_file *file,
      const char *buf, size_t buflen, void *payload
    );
    void (*free_signature)(void *sig, void *payload);
    int (*similarity)(int *score, void *siga, void *sigb, void *payload);
    void *payload;
  } git_diff_similarity_metric;

  typedef struct git_diff_find_options {
    unsigned int version;
    uint32_t     flags;
    uint16_t     rename_threshold;
    uint16_t     rename_from_rewrite_threshold;
    uint16_t     copy_threshold;
    uint16_t     break_rewrite_threshold;
    size_t       rename_limit;
    git_diff_similarity_metric *metric;
  } git_diff_find_options;

  typedef int (* git_apply_delta_cb)(const git_diff_delta *delta, void *payload);
  typedef int (* git_apply_hunk_cb)(const git_diff_hunk *hunk, void *payload);

  typedef struct git_apply_options {
    unsigned int version; /**< The version */
    git_apply_delta_cb delta_cb;
    git_apply_hunk_cb hunk_cb;
    void *payload;
    unsigned int flags;
  } git_apply_options;

  typedef struct git_status_entry {
    unsigned int status;
    struct git_diff_delta *head_to_index;
    struct git_diff_delta *index_to_workdir;
  } git_status_entry;

  typedef struct git_status_options {
	  unsigned int     version;
	  int              show;
	  unsigned int     flags;
	  git_strarray     pathspec;
	  struct git_tree* baseline;
	  uint16_t         rename_threshold;
  } git_status_options;

  typedef struct {
    int32_t seconds;
    /* nsec should not be stored as time_t compatible */
    uint32_t nanoseconds;
  } git_index_time;

  typedef struct git_index_entry {
    git_index_time ctime;
    git_index_time mtime;

    uint32_t dev;
    uint32_t ino;
    uint32_t mode;
    uint32_t uid;
    uint32_t gid;
    uint32_t file_size;

    git_oid id;

    uint16_t flags;
    uint16_t flags_extended;

    const char *path;
  } git_index_entry;

  int git_libgit2_init();
  int git_libgit2_shutdown();
  int git_libgit2_opts(int option, ...);

  void git_strarray_dispose(git_strarray *array);

  int git_buf_grow(git_buf *buffer, size_t target_size);
  void git_buf_dispose(git_buf *buffer);

  int git_blob_lookup(git_blob **blob, git_repository *repo, const git_oid *id);
  const void * git_blob_rawcontent(const git_blob *blob);
  int git_blob_is_binary(const git_blob *blob);
  git_object_size_t git_blob_rawsize(const git_blob *blob);
  void git_blob_free(git_blob *blob);

  char * git_oid_tostr(char *out, size_t n, const git_oid *id);
  int git_oid_equal(const git_oid *a, const git_oid *b);

  char git_diff_status_char(unsigned int status);
  int git_message_prettify(git_buf *out, const char *message, int strip_comments, char comment_char);

  void git_object_free(git_object *object);
  const git_oid * git_object_id(const git_object *obj);

  int git_apply(git_repository *repo, git_diff *diff, unsigned int location, const git_apply_options *options);

  int git_commit_lookup(git_commit **commit, git_repository *repo, const git_oid *id);
  int git_commit_lookup_prefix(git_commit **commit, git_repository *repo, const git_oid *id, size_t len);
  void git_commit_free(git_commit *commit);
  const git_signature * git_commit_author(const git_commit *commit);
  const git_oid * git_commit_id(const git_commit *commit);
  git_repository * git_commit_owner(const git_commit *commit);
  const char * git_commit_message(const git_commit *commit);
  const char * git_commit_message_encoding(const git_commit *commit);
  unsigned int git_commit_parentcount(const git_commit *commit);
  int git_commit_parent(git_commit **out, const git_commit *commit, unsigned int n);
  const git_oid * git_commit_parent_id(const git_commit *commit, unsigned int n);
  int git_commit_create_v(
    git_oid *id,
    git_repository *repo,
    const char *update_ref,
    const git_signature *author,
    const git_signature *committer,
    const char *message_encoding,
    const char *message,
    const git_tree *tree,
    size_t parent_count,
    ...
  );
  int git_commit_amend(
    git_oid *id,
    const git_commit *commit_to_amend,
    const char *update_ref,
    const git_signature *author,
    const git_signature *committer,
    const char *message_encoding,
    const char *message,
    const git_tree *tree
  );

  int git_config_open_default(git_config **out);
  int git_config_open_level(git_config **out, const git_config *parent, int level);
  void git_config_free(git_config *cfg);
  int git_config_get_entry(git_config_entry **out, const git_config *cfg, const char *name);
  int git_config_get_int32(int32_t *out, const git_config *cfg, const char *name);
  int git_config_get_int64(int64_t *out, const git_config *cfg, const char *name);
  int git_config_get_bool(int *out, const git_config *cfg, const char *name);
  int git_config_get_path(git_buf *out, const git_config *cfg, const char *name);
  int git_config_get_string(const char **out, const git_config *cfg, const char *name);
  int git_config_get_string_buf(git_buf *out, const git_config *cfg, const char *name);
  void git_config_entry_free(git_config_entry *entry);
  int git_config_iterator_new(git_config_iterator **out, const git_config *cfg);
  int git_config_next(git_config_entry **entry, git_config_iterator *iter);
  void git_config_iterator_free(git_config_iterator *iter);

  int git_diff_find_similar(git_diff *diff, const git_diff_find_options *options);
  int git_diff_index_to_workdir(git_diff **diff, git_repository *repo, git_index *index, const git_diff_options *opts);
  int git_diff_tree_to_index(git_diff **diff, git_repository *repo, git_tree *old_tree, git_index *index, const git_diff_options *opts);
  int git_diff_tree_to_workdir(git_diff **diff, git_repository *repo, git_tree *old_tree, const git_diff_options *opts);
  int git_diff_to_buf(git_buf *out, git_diff *diff, unsigned int format);
  int git_diff_from_buffer(git_diff **out, const char *content, size_t content_len);
  int git_diff_get_stats(git_diff_stats **out, git_diff *diff);
  const git_diff_delta * git_diff_get_delta(const git_diff *diff, size_t idx);
  size_t git_diff_num_deltas(const git_diff *diff);
  void git_diff_free(git_diff *diff);

  int git_diff_stats_to_buf(git_buf *out, const git_diff_stats *stats, unsigned int format, size_t width);
  size_t git_diff_stats_files_changed(const git_diff_stats *stats);
  size_t git_diff_stats_insertions(const git_diff_stats *stats);
  size_t git_diff_stats_deletions(const git_diff_stats *stats);
  void git_diff_stats_free(git_diff_stats *stats);

  int git_patch_from_diff(git_patch **out, git_diff *diff, size_t idx);
  int git_patch_to_buf(git_buf *out, git_patch *patch);
  size_t git_patch_num_hunks(const git_patch *patch);
  int git_patch_get_hunk(const git_diff_hunk **out, size_t *lines_in_hunk, git_patch *patch, size_t hunk_idx);
  int git_patch_get_line_in_hunk(const git_diff_line **out, git_patch *patch, size_t hunk_idx, size_t line_of_hunk);
  int git_patch_num_lines_in_hunk(const git_patch *patch, size_t hunk_idx);
  int git_patch_line_stats(size_t *total_context, size_t *total_additions, size_t *total_deletions, const git_patch *patch);
  void git_patch_free(git_patch *patch);

  const char * git_reference_shorthand(const git_reference *ref);
  const char * git_reference_name(const git_reference *ref);
  int git_reference_resolve(git_reference **out, const git_reference *ref);
  void git_reference_free(git_reference *ref);
  int git_reference_type(const git_reference *ref);
  const git_oid * git_reference_target(const git_reference *ref);
  int git_reference_peel(git_object **out, const git_reference *ref, int type);
  int git_reference_name_to_id(git_oid *out, git_repository *repo, const char *name);
  int git_reference_lookup(git_reference **out, git_repository *repo, const char *name);
  const char * git_reference_symbolic_target(const git_reference *ref);

  int git_revwalk_new(git_revwalk **walker, git_repository *repo);
  int git_revwalk_push(git_revwalk *walk, const git_oid *oid);
  int git_revwalk_push_head(git_revwalk *walk);
  int git_revwalk_push_ref(git_revwalk *walk, const char *refname);
  int git_revwalk_next(git_oid *oid, git_revwalk *walk);
  int git_revwalk_hide(git_revwalk *walk, const git_oid *oid);
  void git_revwalk_sorting(git_revwalk *walk, unsigned int sort_mode);
  void git_revwalk_free(git_revwalk *walk);
  int git_revwalk_reset(git_revwalk *walker);

  int git_remote_lookup(git_remote **out, git_repository *repo, const char *name);
  int git_remote_list(git_strarray *out, git_repository *repo);
  const char * git_remote_name(const git_remote *remote);
  const char * git_remote_url(const git_remote *remote);
  const char * git_remote_pushurl(const git_remote *remote);
  int git_remote_default_branch(git_buf *out, git_remote *remote);
  int git_remote_disconnect(git_remote *remote);
  void git_remote_free(git_remote *remote);

  int git_branch_iterator_new(git_branch_iterator **out, git_repository *repo, unsigned int list_flags);
  int git_branch_next(git_reference **out, unsigned int *out_type, git_branch_iterator *iter);
  void git_branch_iterator_free(git_branch_iterator *iter);
  int git_branch_upstream(git_reference **out, const git_reference *branch);
  int git_branch_remote_name(git_buf *out, git_repository *repo, const char *refname);
  int git_branch_upstream_remote(git_buf *buf, git_repository *repo, const char *refname);
  int git_branch_upstream_name(git_buf *out, git_repository *repo, const char *refname);
  int git_branch_lookup(git_reference **out, git_repository *repo, const char *branch_name, unsigned int branch_type);

  int git_repository_open_ext(git_repository **out, const char *path, unsigned int flags, const char *ceiling_dirs);
  void git_repository_free(git_repository *repo);
  const char* git_repository_path(const git_repository *repo);
  int git_repository_is_empty(git_repository *repo);
  int git_repository_is_bare(const git_repository *repo);
  int git_repository_head_detached(git_repository *repo);
  int git_repository_head(git_reference **out, git_repository *repo);
  int git_repository_index(git_index **out, git_repository *repo);
  int git_repository_config(git_config **out, git_repository *repo);

  void git_index_free(git_index *index);
  int git_index_read(git_index *index, int force);
  int git_index_write(git_index *index);
  int git_index_write_tree(git_oid *out, git_index *index);
  int git_index_add_bypath(git_index *index, const char *path);
  int git_index_remove_bypath(git_index *index, const char *path);
  int git_index_remove_directory(git_index *index, const char *dir, int stage);
  size_t git_index_entrycount(const git_index *index);
  int git_index_has_conflicts(const git_index *index);
  const git_index_entry * git_index_get_bypath(git_index *index, const char *path, int stage);

  int git_status_list_new(git_status_list **out, git_repository *repo, const git_status_options *opts);
  void git_status_list_free(git_status_list *statuslist);
  size_t git_status_list_entrycount(git_status_list *statuslist);
  const git_status_entry* git_status_byindex(git_status_list *statuslist, size_t idx);
  int git_status_should_ignore(int *ignored, git_repository *repo, const char *path);
  int git_status_file(unsigned int *status_flags, git_repository *repo, const char *path);

  int git_tree_lookup(git_tree **out, git_repository *repo, const git_oid *id);
  void git_tree_free(git_tree *tree);
  size_t git_tree_entrycount(const git_tree *tree);
  int git_tree_entry_bypath(git_tree_entry **out, const git_tree *root, const char *path);

  const git_oid * git_tree_entry_id(const git_tree_entry *entry);
  void git_tree_entry_free(git_tree_entry *entry);

  int git_reset_default(git_repository *repo, const git_object *target, const git_strarray_readonly *pathspecs);

  int git_graph_ahead_behind(size_t *ahead, size_t *behind, git_repository *repo, const git_oid *local, const git_oid *upstream);
  int git_graph_descendant_of(git_repository *repo, const git_oid *commit, const git_oid *ancestor);

  int git_signature_default(git_signature **out, git_repository *repo);
  void git_signature_free(git_signature *sig);

  int git_tag_lookup(git_tag **out, git_repository *repo, const git_oid *id);
  const char * git_tag_name(const git_tag *tag);
  void git_tag_free(git_tag *tag);
]]


---@class Libgit2Module
---@field C ffi.namespace*
local M = {
  C = ffi.load "libgit2",
}

M.char_array = ffi.typeof("char[?]")
M.const_char_pointer_array = ffi.typeof("const char *[?]")
M.unsigned_int_array = ffi.typeof("unsigned int[?]")
M.size_t_array = ffi.typeof("size_t[?]")
M.int64_array = ffi.typeof("int64_t[?]")
M.int_array = ffi.typeof("int[?]")


---@type ffi.ctype* git_buf[1]
M.git_buf = ffi.typeof("git_buf[1]")

---@type ffi.ctype* git_config*[1]
M.git_config_double_pointer = ffi.typeof("git_config*[1]")
---@type ffi.ctype* git_config* pointer
M.git_config_pointer = ffi.typeof("git_config*")

---@type ffi.ctype* git_config_entry*[1]
M.git_config_entry_double_pointer = ffi.typeof("git_config_entry*[1]")

---@type ffi.ctype* git_config_iterator*[1]
M.git_config_iterator_double_pointer = ffi.typeof("git_config_iterator*[1]")

---@type ffi.ctype* git_oid[1]
M.git_oid = ffi.typeof("git_oid[1]")

---@type ffi.ctype* git_strarray_readonly[1]
M.git_strarray_readonly = ffi.typeof("git_strarray_readonly[1]")
---@type ffi.ctype* git_strarray[1]
M.git_strarray = ffi.typeof("git_strarray[1]")

---@type ffi.ctype* git_object **
M.git_object_double_pointer = ffi.typeof("git_object*[1]")
---@type ffi.ctype* git_object *
M.git_object_pointer = ffi.typeof("git_object*")

---@type ffi.ctype* git_commit **
M.git_commit_double_pointer = ffi.typeof("git_commit*[1]")
---@type ffi.ctype* git_commit *
M.git_commit_pointer = ffi.typeof("git_commit*")

---@type ffi.ctype* git_blob **
M.git_blob_double_pointer = ffi.typeof("git_blob*[1]")
---@type ffi.ctype* git_blob *
M.git_blob_pointer = ffi.typeof("git_blob*")

---@type ffi.ctype* git_tree **
M.git_tree_double_pointer = ffi.typeof("git_tree*[1]")
---@type ffi.ctype* git_tree *
M.git_tree_pointer = ffi.typeof("git_tree*")

---@type ffi.ctype* git_tree_entry*[1]
M.git_tree_entry_double_pointer = ffi.typeof("git_tree_entry*[1]")
---@type ffi.ctype* git_tree_entry*
M.git_tree_entry_pointer = ffi.typeof("git_tree_entry*")

---@type ffi.ctype* git_apply_options[1]
M.git_apply_options = ffi.typeof("git_apply_options[1]")

---@type ffi.ctype* struct git_diff **
M.git_diff_double_pointer = ffi.typeof("git_diff*[1]")
---@type ffi.ctype* struct git_diff *
M.git_diff_pointer = ffi.typeof("git_diff*")

---@type ffi.ctype* struct git_diff_options [1]
M.git_diff_options = ffi.typeof("git_diff_options[1]")

---@type ffi.ctype* struct git_diff_find_options [1]
M.git_diff_find_options = ffi.typeof("git_diff_find_options[1]")

---@type ffi.ctype* struct git_diff_hunk *[1]
M.git_diff_hunk_double_pointer = ffi.typeof("const git_diff_hunk*[1]")

---@type ffi.ctype* const struct git_diff_line **out
M.git_diff_line_double_pointer = ffi.typeof("const git_diff_line*[1]")

---@type ffi.ctype* struct git_diff_stats *[1]
M.git_diff_stats_double_pointer = ffi.typeof("git_diff_stats*[1]")

---@type ffi.ctype* struct git_patch **
M.git_patch_double_pointer = ffi.typeof("git_patch*[1]")
---@type ffi.ctype* struct git_patch *
M.git_patch_pointer = ffi.typeof("git_patch*")

---@type ffi.ctype* struct git_repository**
M.git_repository_double_pointer = ffi.typeof("git_repository*[1]")
---@type ffi.ctype* struct git_repository*
M.git_repository_pointer = ffi.typeof("git_repository*")

---@type ffi.ctype* struct git_reference*[1]
M.git_reference_double_pointer = ffi.typeof("git_reference*[1]")

---@type ffi.ctype* struct git_reference*
M.git_reference_pointer = ffi.typeof("git_reference*")

---@type ffi.ctype* struct git_remote**
M.git_remote_double_pointer = ffi.typeof("git_remote*[1]")
---@type ffi.ctype* struct git_remote*
M.git_remote_pointer = ffi.typeof("git_remote*")

---@type ffi.ctype* struct git_revwalk**
M.git_revwalk_double_pointer = ffi.typeof("git_revwalk*[1]")

---@type ffi.ctype* struct git_revwalk*
M.git_revwalk_pointer = ffi.typeof("git_revwalk*")

---@type ffi.ctype* git_signature **
M.git_signature_double_pointer = ffi.typeof("git_signature*[1]")
---@type ffi.ctype* git_signature *
M.git_signature_pointer = ffi.typeof("git_signature*")

---@type ffi.ctype* git_status_options[1]
M.git_status_options = ffi.typeof("git_status_options[1]")

---@type ffi.ctype* struct git_status_list*[1]
M.git_status_list_double_pointer = ffi.typeof("git_status_list*[1]")

---@type ffi.ctype* git_tag*[1]
M.git_tag_double_pointer = ffi.typeof("git_tag*[1]")
---@type ffi.ctype* git_tag*
M.git_tag_pointer = ffi.typeof("git_tag*")

---@type ffi.ctype* git_index**
M.git_index_double_pointer = ffi.typeof("git_index*[1]")
---@type ffi.ctype* git_index*
M.git_index_pointer = ffi.typeof("git_index*")

---@type ffi.ctype* struct git_branch_iterator *[1]
M.git_branch_iterator_double_pointer = ffi.typeof("git_branch_iterator *[1]")


-- ==========================
-- | libgit2 struct version |
-- ==========================

M.GIT_APPLY_OPTIONS_VERSION = 1
M.GIT_DIFF_FIND_OPTIONS_VERSION = 1
M.GIT_DIFF_OPTIONS_VERSION = 1
M.GIT_FETCH_OPTIONS_VERSION = 1
M.GIT_PROXY_OPTIONS_VERSION = 1
M.GIT_REMOTE_CALLBACKS_VERSION = 1
M.GIT_STATUS_OPTIONS_VERSION = 1

-- ================
-- | libgit2 enum |
-- ================


---@enum GIT_OPT
M.GIT_OPT = {
	GET_MWINDOW_SIZE                    = 0,
	SET_MWINDOW_SIZE                    = 1,
	GET_MWINDOW_MAPPED_LIMIT            = 2,
	SET_MWINDOW_MAPPED_LIMIT            = 3,
	GET_SEARCH_PATH                     = 4,
	SET_SEARCH_PATH                     = 5,
	SET_CACHE_OBJECT_LIMIT              = 6,
	SET_CACHE_MAX_SIZE                  = 7,
	ENABLE_CACHING                      = 8,
	GET_CACHED_MEMORY                   = 9,
	GET_TEMPLATE_PATH                   = 10,
	SET_TEMPLATE_PATH                   = 11,
	SET_SSL_CERT_LOCATIONS              = 12,
	SET_USER_AGENT                      = 13,
	ENABLE_STRICT_OBJECT_CREATION       = 14,
	ENABLE_STRICT_SYMBOLIC_REF_CREATION = 15,
	SET_SSL_CIPHERS                     = 16,
	GET_USER_AGENT                      = 17,
	ENABLE_OFS_DELTA                    = 18,
	ENABLE_FSYNC_GITDIR                 = 19,
	GET_WINDOWS_SHAREMODE               = 20,
	SET_WINDOWS_SHAREMODE               = 21,
	ENABLE_STRICT_HASH_VERIFICATION     = 22,
	SET_ALLOCATOR                       = 23,
	ENABLE_UNSAVED_INDEX_SAFETY         = 24,
	GET_PACK_MAX_OBJECTS                = 25,
	SET_PACK_MAX_OBJECTS                = 26,
	DISABLE_PACK_KEEP_FILE_CHECKS       = 27,
	ENABLE_HTTP_EXPECT_CONTINUE         = 28,
	GET_MWINDOW_FILE_LIMIT              = 29,
	SET_MWINDOW_FILE_LIMIT              = 30,
	SET_ODB_PACKED_PRIORITY             = 31,
	SET_ODB_LOOSE_PRIORITY              = 32,
	GET_EXTENSIONS                      = 33,
	SET_EXTENSIONS                      = 34,
	GET_OWNER_VALIDATION                = 35,
	SET_OWNER_VALIDATION                = 36,
	GET_HOMEDIR                         = 37,
	SET_HOMEDIR                         = 38,
	SET_SERVER_CONNECT_TIMEOUT          = 39,
	GET_SERVER_CONNECT_TIMEOUT          = 40,
	SET_SERVER_TIMEOUT                  = 41,
	GET_SERVER_TIMEOUT                  = 42,
}

---@enum GIT_APPLY_LOCATION
M.GIT_APPLY_LOCATION = {
  WORKDIR = 0,
  INDEX   = 1,
  BOTH    = 2,
}

---@enum GIT_BRANCH
M.GIT_BRANCH = {
  LOCAL  = 1,
  REMOTE = 2,
  ALL    = 3, -- GIT_BRANCH_LOCAL|GIT_BRANCH_REMOTE,
}

---@enum GIT_CONFIG_LEVEL
M.GIT_CONFIG_LEVEL = {
  -- System-wide on Windows, for compatibility with portable git
  PROGRAMDATA = 1,
  -- System-wide configuration file; /etc/gitconfig on Linux systems */
  SYSTEM = 2,
  -- XDG compatible configuration file; typically ~/.config/git/config */
  XDG = 3,
  -- User-specific configuration file (also called Global configuration
  -- file); typically ~/.gitconfig
  GLOBAL = 4,
  -- Repository specific configuration file; $WORK_DIR/.git/config on
  -- non-bare repos
  LOCAL = 5,
  -- Application specific configuration file; freely defined by applications
  APP = 6,
  -- Represents the highest level available config file (i.e. the most
  -- specific config file available that actually is loaded)
  HIGHEST_LEVEL = -1
}
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

---@enum GIT_INDEX_STAGE
M.GIT_INDEX_STAGE = {
  ANY      = -1,-- Match any index stage.
  NORMAL   = 0, -- A normal staged file in the index.
  ANCESTOR = 1, -- The ancestor side of a conflict.
  OURS     = 2, -- The "ours" side of a conflict.
  THEIRS   = 3, -- The "theirs" side of a conflict.
}

---@enum GIT_REFERENCE
M.GIT_REFERENCE = {
  INVALID  = 0, -- Invalid reference
  DIRECT   = 1, -- A reference that points at an object id
  SYMBOLIC = 2, -- A reference that points at another reference
  ALL      = 3, -- Both GIT_REFERENCE_DIRECT | GIT_REFERENCE_SYMBOLIC
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

---@enum GIT_SORT
M.GIT_SORT = {
  NONE        = 0, -- 0, default method from `git`: reverse chronological order
  TOPOLOGICAL = 1, -- 1 << 0, Sort the repository contents in topological order
  TIME        = 2, -- 1 << 1, Sort the repository contents by commit time.
  REVERSE     = 4, -- 1 << 2, Iterate through the repository contents in reverse order.
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

  IGNORED          = 0x4000, -- 1u << 14
  CONFLICTED       = 0x8000, -- 1u << 15
}

---@enum GIT_STATUS_SHOW
M.GIT_STATUS_SHOW = {
  INDEX_AND_WORKDIR = 0,
	INDEX_ONLY        = 1,
	WORKDIR_ONLY      = 2
}

---@enum GIT_STATUS_OPT
M.GIT_STATUS_OPT = {
	INCLUDE_UNTRACKED               = 1,      -- (1u << 0),
	INCLUDE_IGNORED                 = 2,      -- (1u << 1),
	INCLUDE_UNMODIFIED              = 4,      -- (1u << 2),
	EXCLUDE_SUBMODULES              = 8,      -- (1u << 3),
	RECURSE_UNTRACKED_DIRS          = 16,     -- (1u << 4),
	DISABLE_PATHSPEC_MATCH          = 32,     -- (1u << 5),
	RECURSE_IGNORED_DIRS            = 64,     -- (1u << 6),
	RENAMES_HEAD_TO_INDEX           = 128,    -- (1u << 7),
	RENAMES_INDEX_TO_WORKDIR        = 256,    -- (1u << 8),
	SORT_CASE_SENSITIVELY           = 512,    -- (1u << 9),
	SORT_CASE_INSENSITIVELY         = 1024,   -- (1u << 10),
	RENAMES_FROM_REWRITES           = 2048,   -- (1u << 11),
	NO_REFRESH                      = 4096,   -- (1u << 12),
	UPDATE_INDEX                    = 8192,   -- (1u << 13),
	INCLUDE_UNREADABLE              = 0x4000, -- (1u << 14),
	INCLUDE_UNREADABLE_AS_UNTRACKED = 0x8000, --(1u << 15)
}

---@enum GIT_DELTA
M.GIT_DELTA = {
  UNMODIFIED = 0,  -- no changes
	ADDED      = 1,	 -- entry does not exist in old version
	DELETED    = 2,	 -- entry does not exist in new version
	MODIFIED   = 3,  -- entry content changed between old and new
	RENAMED    = 4,  -- entry was renamed between old and new
	COPIED     = 5,  -- entry was copied from another old entry
	IGNORED    = 6,  -- entry is ignored item in workdir
	UNTRACKED  = 7,  -- entry is untracked item in workdir
	TYPECHANGE = 8,  -- type of entry changed between old and new
	UNREADABLE = 9,  -- entry is unreadable
	CONFLICTED = 10  -- entry in the index is conflicted
}

---@enum GIT_REPOSITORY_OPEN
M.GIT_REPOSITORY_OPEN = {
  NO_SEARCH = 1,

	--  Unless this flag is set, open will not continue searching across
	-- filesystem boundaries (i.e. when `st_dev` changes from the `stat`
	-- system call).  For example, searching in a user's home directory at
	-- "/home/user/source/" will not return "/.git/" as the found repo if
	-- "/" is a different filesystem than "/home".
  CROSS_FS  = 2,

	-- Open repository as a bare repo regardless of core.bare config, and
	-- defer loading config file for faster setup.
	-- Unlike `git_repository_open_bare`, this can follow gitlinks.
  BARE      = 4,

  NO_DOTGIT = 8,
  FROM_ENV  = 16,
}

---@enum GIT_DIFF_FORMAT
M.GIT_DIFF_FORMAT = {
  PATCH        = 1, -- full git diff
  PATCH_HEADER = 2, -- just the file headers of patch
  RAW          = 3, -- like git diff --raw
  NAME_ONLY    = 4, -- like git diff --name-only
  NAME_STATUS  = 5, -- like git diff --name-status
  PATCH_ID     = 6, -- git diff as used by git patch-id
}

---@enum GIT_DIFF
M.GIT_DIFF = {
  NORMAL                 = 0,    --0: Normal diff, the default
  REVERSE                = 1,    --(1 << 0): Reverse the sides of the diff
  INCLUDE_IGNORED        = 2,    --(1 << 1): Include ignored files in the diff
  RECURSE_IGNORED_DIRS   = 4,    --(1 << 2): adds files under the ignored directory as IGNORED entries
  INCLUDE_UNTRACKED      = 8,    --(1 << 3): Include untracked files in the diff
  RECURSE_UNTRACKED_DIRS = 0x10, --(1 << 4): adds files under untracked directories as UNTRACKED entries
	INCLUDE_UNMODIFIED     = 0x20, --(1 << 5): include unmodified files in the diff
  -- a type change between files will be converted into a
  -- DELETED record for the old and an ADDED record for the new; this
  -- options enabled the generation of TYPECHANGE delta records
  INCLUDE_TYPECHANGE     = 0x40, --(1 << 6)
  -- Even with GIT_DIFF_INCLUDE_TYPECHANGE, blob->tree changes still
	-- generally show as a DELETED blob.  This flag tries to correctly
	-- label blob->tree transitions as TYPECHANGE records with new_file's
	-- mode set to tree.  Note: the tree SHA will not be available.
  INCLUDE_TYPECHANGE_TREES = 0x80,  --(1 << 7)
  IGNORE_FILEMODE          = 0x100, --(1u << 8): Ignore file mode changes
	IGNORE_SUBMODULES        = 0x200, --(1u << 9): Treat all submodules as unmodified
  IGNORE_CASE              = 0x400, --(1u << 10): case insensitive for filename comparisons
  INCLUDE_CASECHANGE       = 0x800, --(1u << 11): combined with `IGNORE_CASE` to specify that a file that has changed case will be returned as an add/delete pair.

  -- If the pathspec is set in the diff options, this flags indicates
	-- that the paths will be treated as literal paths instead of fnmatch patterns.
  -- Each path in the list must either be a full path to a file or a directory.
  -- (A trailing slash indicates that the path will _only_ match a directory).
  -- If a directory is specified, all children will be included.
  DISABLE_PATHSPEC_MATCH = 0x1000, --(1u << 12)

	-- Disable updating of the `binary` flag in delta records.  This is
	-- useful when iterating over a diff if you don't need hunk and data
	-- callbacks and want to avoid having to load file completely.
	SKIP_BINARY_CHECK = 0x2000, --(1u << 13)

	-- When diff finds an untracked directory, to match the behavior of
	-- core Git, it scans the contents for IGNORED and UNTRACKED files.
	-- If *all* contents are IGNORED, then the directory is IGNORED; if
	-- any contents are not IGNORED, then the directory is UNTRACKED.
	-- This is extra work that may not matter in many cases. This flag
	-- turns off that scan and immediately labels an untracked directory
	-- as UNTRACKED (changing the behavior to not match core Git).
	ENABLE_FAST_UNTRACKED_DIRS = 0x4000, --(1u << 14)

	-- When diff finds a file in the working directory with stat
	-- information different from the index, but the OID ends up being the
	-- same, write the correct stat information into the index.
  -- Note: without this flag, diff will always leave the index untouched.
	UPDATE_INDEX                    = 0x8000,  --(1u << 15)
	INCLUDE_UNREADABLE              = 0x10000, -- 1u << 16): Include unreadable files in the diff
  INCLUDE_UNREADABLE_AS_UNTRACKED = 0x20000, --(1u << 17): Include unreadable files as UNTRACKED

  -- Options controlling how output will be generated

	-- Use a heuristic that takes indentation and whitespace into account
	-- which generally can produce better diffs when dealing with ambiguous
	-- diff hunks.
	INDENT_HEURISTIC         = 0x40000,   --(1u << 18)
	IGNORE_BLANK_LINES       = 0x80000,   --(1u << 19): Ignore blank lines
  FORCE_TEXT               = 0x100000,  --(1u << 20): Treat all files as text, disabling binary attributes & detection
  FORCE_BINARY             = 0x200000,  --(1u << 21): Treat all files as binary, disabling text diffs
  IGNORE_WHITESPACE        = 0x400000,  --(1u << 22): Ignore all whitespaces
  IGNORE_WHITESPACE_CHANGE = 0x800000,  --(1u << 23): Ignore changes in amount of whitespace
	IGNORE_WHITESPACE_EOL    = 0x1000000, --(1u << 24): Ignore whitespace at end of line

	-- When generating patch text, include the content of untracked files.
  -- This automatically turns on GIT_DIFF_INCLUDE_UNTRACKED but
	-- it does not turn on GIT_DIFF_RECURSE_UNTRACKED_DIRS.
  -- Add that flag if you want the content of every single UNTRACKED file.
	SHOW_UNTRACKED_CONTENT = 0x2000000,  --(1u << 25)

	-- When generating output, include the names of unmodified files if
	-- they are included in the git_diff. Normally these are skipped in
	-- the formats that list files (e.g. name-only, name-status, raw).
	-- Even with this, these will not be included in patch format.
	SHOW_UNMODIFIED = 0x4000000,  --(1u << 26)

	PATIENCE        = 0x10000000, --(1u << 28): Use the "patience diff" algorithm
	MINIMAL         = 0x20000000, --(1u << 29): Take extra time to find minimal diff
	-- Include the necessary deflate / delta information so that `git-apply`
	-- can apply given diff information to binary files.
	SHOW_BINARY     = 0x40000000, --(1u << 30)
}

---@enum GIT_DIFF_FIND
M.GIT_DIFF_FIND = {
  FIND_BY_CONFIG                  = 0,      -- Obey `diff.renames
	FIND_RENAMES                    = 1,      -- (1u << 0): Look for renames? (`--find-renames`)
  FIND_RENAMES_FROM_REWRITES      = 2,      -- (1u << 1)
  FIND_COPIES                     = 4,      -- (1u << 2)
  FIND_COPIES_FROM_UNMODIFIED     = 8,      -- (1u << 3)
  FIND_REWRITES                   = 16,     -- (1u << 4)
  BREAK_REWRITES                  = 32,     -- (1u << 5),
  FIND_AND_BREAK_REWRITES         = 48,     -- (GIT_DIFF_FIND_REWRITES | GIT_DIFF_BREAK_REWRITES)
  FIND_FOR_UNTRACKED              = 64,     -- (1u << 6)
  FIND_ALL                        = 0xff,   -- (0x0ff) Turn on all finding features.
  FIND_IGNORE_LEADING_WHITESPACE  = 0,
  FIND_IGNORE_WHITESPACE          = 0x1000, -- (1u << 12),
  FIND_DONT_IGNORE_WHITESPACE     = 0x2000, -- (1u << 13),
  FIND_EXACT_MATCH_ONLY           = 0x4000, -- (1u << 14),
  BREAK_REWRITES_FOR_RENAMES_ONLY = 0x8000, -- (1u << 15),
  FIND_REMOVE_UNMODIFIED          = 0x10000,-- (1u << 16)
}

---@enum GIT_SUBMODULE
M.GIT_SUBMODULE = {
	IGNORE_UNSPECIFIED = -1, -- use the submodule's configuration
	IGNORE_NONE        = 1,  -- any change or untracked == dirty
	IGNORE_UNTRACKED   = 2,  -- dirty if tracked files change
	IGNORE_DIRTY       = 3,  -- only dirty if HEAD moved
	IGNORE_ALL         = 4   -- never dirty
}

---@enum GIT_DIFF_LINE
M.GIT_DIFF_LINE = {
	CONTEXT       = ' ',
	ADDITION      = '+',
	DELETION      = '-',
	CONTEXT_EOFNL = '=', --Both files have no LF at end
	ADD_EOFNL     = '>', --Old has no LF at end, new does
	DEL_EOFNL     = '<', --Old has LF at end, new does not
	FILE_HDR      = 'F',
	HUNK_HDR      = 'H',
	BINARY        = 'B'  -- For "Binary files x and y differ"
}


-- Inits helper

local NULL = ffi.cast("void*", nil)

M.GIT_APPLY_OPTIONS_INIT = {{  M.GIT_APPLY_OPTIONS_VERSION }}
M.GIT_STATUS_OPTIONS_INIT = { { M.GIT_STATUS_OPTIONS_VERSION } }
M.GIT_DIFF_OPTIONS_INIT = {{
  M.GIT_STATUS_OPTIONS_VERSION, 0, M.GIT_SUBMODULE.IGNORE_UNSPECIFIED,
  { NULL, 0 }, NULL, NULL, NULL, 3
}}
M.GIT_DIFF_FIND_OPTIONS_INIT = {{ M.GIT_DIFF_FIND_OPTIONS_VERSION }}


return M
