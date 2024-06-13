local ffi = require "ffi"

-- =====================
-- | Libgit2 C section |
-- =====================

--- Load libgit2 via ffi
ffi.cdef [[
  typedef uint64_t git_object_size_t;
  typedef int64_t git_off_t;
  typedef int64_t git_time_t;

  typedef struct git_annotated_commit git_annotated_commit;
  typedef struct git_blame git_blame;
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
  typedef struct git_rebase git_rebase;
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

  typedef struct git_blame_hunk {
	  size_t lines_in_hunk;
	  git_oid final_commit_id;
	  size_t final_start_line_number;
	  git_signature *final_signature;
	  git_oid orig_commit_id;
	  const char *orig_path;
	  size_t orig_start_line_number;
	  git_signature *orig_signature;
	  char boundary;
  } git_blame_hunk;

  typedef struct git_blame_options {
	  unsigned int version;
	  uint32_t flags;
	  uint16_t min_match_characters;
	  git_oid newest_commit;
	  git_oid oldest_commit;
    size_t min_line;
    size_t max_line;
  } git_blame_options;

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

  typedef int (*git_commit_create_cb)(
    git_oid *out,
    const git_signature *author,
    const git_signature *committer,
    const char *message_encoding,
    const char *message,
    const git_tree *tree,
    size_t parent_count,
    const git_commit **parents,
    void *payload
  );
  typedef int (*git_checkout_notify_cb)(
    unsigned int why,
    const char *path,
    const git_diff_file *baseline,
    const git_diff_file *target,
    const git_diff_file *workdir,
    void *payload
  );
  typedef void (*git_checkout_progress_cb)(
    const char *path,
    size_t completed_steps,
    size_t total_steps,
    void *payload
  );
  typedef struct git_checkout_perfdata {
    size_t mkdir_calls;
    size_t stat_calls;
    size_t chmod_calls;
  } git_checkout_perfdata;
  typedef void (*git_checkout_perfdata_cb)(
    const git_checkout_perfdata *perfdata,
    void *payload
  );

  typedef struct git_checkout_options {
    unsigned int version;
    unsigned int checkout_strategy;
    int disable_filters;    /**< don't apply filters like CRLF conversion */
    unsigned int dir_mode;  /**< default is 0755 */
    unsigned int file_mode; /**< default is 0644 or 0755 as dictated by blob */
    int file_open_flags;    /**< default is O_CREAT | O_TRUNC | O_WRONLY */
    unsigned int notify_flags; /**< see `git_checkout_notify_t` above */
    git_checkout_notify_cb notify_cb;
    void *notify_payload;
    git_checkout_progress_cb progress_cb;
    void *progress_payload;
    git_strarray_readonly paths;
    git_tree *baseline;
    git_index *baseline_index;
    const char *target_directory; /**< alternative checkout path to workdir */
    const char *ancestor_label; /**< the name of the common ancestor side of conflicts */
    const char *our_label; /**< the name of the "our" side of conflicts */
    const char *their_label; /**< the name of the "their" side of conflicts */
    git_checkout_perfdata_cb perfdata_cb;
    void *perfdata_payload;
  } git_checkout_options;

  typedef struct git_merge_options {
    unsigned int version;
    uint32_t flags;
    unsigned int rename_threshold;
    unsigned int target_limit;
    git_diff_similarity_metric *metric;
    unsigned int recursion_limit;
    const char *default_driver;
    unsigned int file_favor;
    uint32_t file_flags;
  } git_merge_options;

  typedef struct git_rebase_options {
    unsigned int version;
    int quiet;
    int inmemory;
    const char *rewrite_notes_ref;
    git_merge_options merge_options;
    git_checkout_options checkout_options;
    git_commit_create_cb commit_create_cb;
    void *reserved;
    void *payload;
  } git_rebase_options;

  typedef struct git_rebase_operation {
    unsigned int type;
    const git_oid id;
    const char *exec;
  } git_rebase_operation;

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

  int git_blame_options_init(git_blame_options *opts, unsigned int version);
  void git_blame_free(git_blame *blame);
  int git_blame_buffer(git_blame **out, git_blame *reference, const char *buffer, size_t buffer_len);
  int git_blame_file(git_blame **out, git_repository *repo, const char *path, git_blame_options *options);
  const git_blame_hunk * git_blame_get_hunk_byindex(git_blame *blame, uint32_t index);
  const git_blame_hunk * git_blame_get_hunk_byline(git_blame *blame, size_t lineno);
  uint32_t git_blame_get_hunk_count(git_blame *blame);

  int git_blob_lookup(git_blob **blob, git_repository *repo, const git_oid *id);
  const void * git_blob_rawcontent(const git_blob *blob);
  int git_blob_is_binary(const git_blob *blob);
  git_object_size_t git_blob_rawsize(const git_blob *blob);
  const void * git_blob_rawcontent(const git_blob *blob);
  void git_blob_free(git_blob *blob);

  int git_checkout_head(git_repository *repo, const git_checkout_options *opts);
  int git_checkout_index(git_repository *repo, git_index *index, const git_checkout_options *opts);
  int git_checkout_tree(git_repository *repo, const git_object *treeish, const git_checkout_options *opts);

  char * git_oid_tostr(char *out, size_t n, const git_oid *id);
  char * git_oid_tostr_s(const git_oid *oid);
  int git_oid_equal(const git_oid *a, const git_oid *b);
  int git_oid_cpy(git_oid *out, const git_oid *src);
  int git_oid_fromstr(git_oid *out, const char *str);
  int git_oid_fromstrp(git_oid *out, const char *str);
  int git_oid_fromstrn(git_oid *out, const char *str, size_t length);

  char git_diff_status_char(unsigned int status);
  int git_message_prettify(git_buf *out, const char *message, int strip_comments, char comment_char);

  void git_object_free(git_object *object);
  int git_object_lookup_bypath(git_object **out, const git_object *treeish, const char *path, int type);
  const git_oid * git_object_id(const git_object *obj);

  int git_apply_options_init(git_apply_options *opts, unsigned int version);
  int git_apply(git_repository *repo, git_diff *diff, unsigned int location, const git_apply_options *options);

  int git_commit_lookup(git_commit **commit, git_repository *repo, const git_oid *id);
  int git_commit_lookup_prefix(git_commit **commit, git_repository *repo, const git_oid *id, size_t len);
  void git_commit_free(git_commit *commit);
  const git_signature * git_commit_author(const git_commit *commit);
  const git_signature * git_commit_committer(const git_commit *commit);
  const git_oid * git_commit_id(const git_commit *commit);
  git_repository * git_commit_owner(const git_commit *commit);
  const char * git_commit_message(const git_commit *commit);
  const char * git_commit_message_encoding(const git_commit *commit);
  const char * git_commit_summary(git_commit *commit);
  const char * git_commit_body(git_commit *commit);
  git_time_t git_commit_time(const git_commit *commit);
  int git_commit_extract_signature(git_buf *signature, git_buf *signed_data, git_repository *repo, git_oid *commit_id, const char *field);
  unsigned int git_commit_parentcount(const git_commit *commit);
  int git_commit_parent(git_commit **out, const git_commit *commit, unsigned int n);
  const git_oid * git_commit_parent_id(const git_commit *commit, unsigned int n);
  int git_commit_tree(git_tree **tree_out, const git_commit *commit);
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
  int git_commit_create(
    git_oid *id,
    git_repository *repo,
    const char *update_ref,
    const git_signature *author,
    const git_signature *committer,
    const char *message_encoding,
    const char *message,
    const git_tree *tree,
    size_t parent_count,
    const git_commit **parents
  );
  int git_commit_create_buffer(
    git_buf *out,
    git_repository *repo,
    const git_signature *author,
    const git_signature *committer,
    const char *message_encoding,
    const char *message,
    const git_tree *tree,
    size_t parent_count,
    const git_commit **parents
  );
  int git_commit_create_with_signature(
    git_oid *out,
    git_repository *repo,
    const char *commit_content,
    const char *signature,
    const char *signature_field
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
  int git_diff_tree_to_tree(git_diff **diff, git_repository *repo, git_tree *old_tree, git_tree *new_tree, const git_diff_options *opts);
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
  int git_reference_set_target(git_reference **out, git_reference *ref, const git_oid *id, const char *log_message);
  int git_reference_peel(git_object **out, const git_reference *ref, int type);
  int git_reference_name_to_id(git_oid *out, git_repository *repo, const char *name);
  int git_reference_lookup(git_reference **out, git_repository *repo, const char *name);
  const char * git_reference_symbolic_target(const git_reference *ref);
  int git_reference_create(git_reference **out, git_repository *repo, const char *name, const git_oid *id, int force, const char *log_message);
  int git_reference_symbolic_create(git_reference **out, git_repository *repo, const char *name, const char *target, int force, const char *log_message);

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
  int git_branch_create(git_reference **out, git_repository *repo, const char *branch_name, const git_commit *target, int force);

  int git_repository_open_ext(git_repository **out, const char *path, unsigned int flags, const char *ceiling_dirs);
  void git_repository_free(git_repository *repo);
  const char* git_repository_path(const git_repository *repo);
  int git_repository_is_empty(git_repository *repo);
  int git_repository_is_bare(const git_repository *repo);
  int git_repository_head_detached(git_repository *repo);
  int git_repository_head(git_reference **out, git_repository *repo);
  int git_repository_index(git_index **out, git_repository *repo);
  int git_repository_config(git_config **out, git_repository *repo);
  int git_repository_set_head(git_repository *repo, const char *refname);
  int git_repository_set_head_detached(git_repository *repo, const git_oid *committish);

  void git_index_free(git_index *index);
  int git_index_read(git_index *index, int force);
  int git_index_write(git_index *index);
  int git_index_write_tree(git_oid *out, git_index *index);
  const char * git_index_path(const git_index *index);
  int git_index_add_from_buffer(git_index *index, const git_index_entry *entry, const void *buffer, size_t len);
  int git_index_add_bypath(git_index *index, const char *path);
  int git_index_remove_bypath(git_index *index, const char *path);
  int git_index_remove_directory(git_index *index, const char *dir, int stage);
  size_t git_index_entrycount(const git_index *index);
  int git_index_has_conflicts(const git_index *index);
  int git_index_conflict_get(const git_index_entry **ancestor_out, const git_index_entry **our_out, const git_index_entry **their_out, git_index *index, const char *path);
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
  const git_oid * git_tree_id(const git_tree *tree);

  int git_tree_entry_bypath(git_tree_entry **out, const git_tree *root, const char *path);
  const git_tree_entry * git_tree_entry_byname(const git_tree *tree, const char *filename);
  const git_tree_entry * git_tree_entry_byid(const git_tree *tree, const git_oid *id);
  const git_tree_entry * git_tree_entry_byindex(const git_tree *tree, size_t idx);

  const git_oid * git_tree_entry_id(const git_tree_entry *entry);
  void git_tree_entry_free(git_tree_entry *entry);
  const char * git_tree_entry_name(const git_tree_entry *entry);
  int git_tree_entry_type(const git_tree_entry *entry);
  int git_tree_entry_to_object(git_object **object_out, git_repository *repo, const git_tree_entry *entry);

  int git_reset_default(git_repository *repo, const git_object *target, const git_strarray_readonly *pathspecs);

  int git_graph_ahead_behind(size_t *ahead, size_t *behind, git_repository *repo, const git_oid *local, const git_oid *upstream);
  int git_graph_descendant_of(git_repository *repo, const git_oid *commit, const git_oid *ancestor);

  int git_signature_default(git_signature **out, git_repository *repo);
  void git_signature_free(git_signature *sig);

  int git_tag_lookup(git_tag **out, git_repository *repo, const git_oid *id);
  const char * git_tag_name(const git_tag *tag);
  void git_tag_free(git_tag *tag);
  int git_tag_list(git_strarray *tag_names, git_repository *repo);

  int git_annotated_commit_from_ref(git_annotated_commit **out, git_repository *repo, const git_reference *ref);
  int git_annotated_commit_from_revspec(git_annotated_commit **out, git_repository *repo, const char *revspec);
  const git_oid * git_annotated_commit_id(const git_annotated_commit *commit);
  const char * git_annotated_commit_ref(const git_annotated_commit *commit);
  void git_annotated_commit_free(git_annotated_commit *commit);

  int git_rebase_init(git_rebase **out, git_repository *repo, const git_annotated_commit *branch, const git_annotated_commit *upstream, const git_annotated_commit *onto, const git_rebase_options *opts);
  int git_rebase_open(git_rebase **out, git_repository *repo, const git_rebase_options *opts);
  const char * git_rebase_orig_head_name(git_rebase *rebase);
  const git_oid * git_rebase_orig_head_id(git_rebase *rebase);
  const char * git_rebase_onto_name(git_rebase *rebase);
  const git_oid * git_rebase_onto_id(git_rebase *rebase);
  size_t git_rebase_operation_entrycount(git_rebase *rebase);
  size_t git_rebase_operation_current(git_rebase *rebase);
  git_rebase_operation * git_rebase_operation_byindex(git_rebase *rebase, size_t idx);
  int git_rebase_inmemory_index(git_index **index, git_rebase *rebase);
  int git_rebase_next(git_rebase_operation **operation, git_rebase *rebase);
  int git_rebase_commit(git_oid *id, git_rebase *rebase, const git_signature *author, const git_signature *committer, const char *message_encoding, const char *message);
  int git_rebase_abort(git_rebase *rebase);
  int git_rebase_finish(git_rebase *rebase, const git_signature *signature);
  void git_rebase_free(git_rebase *rebase);
]]

---@class Libgit2Module
---@field C ffi.namespace*
local M = {}

---@param path string?
M.load_library = function(path)
  if not M.C then
    rawset(M, "C", ffi.load(path or "libgit2"))
  end
end

M.uint32 = ffi.typeof "uint32_t"
M.pointer_t = ffi.typeof "intptr_t"
M.char_pointer = ffi.typeof "char*"
M.char_array = ffi.typeof "char[?]"
M.const_char_pointer_array = ffi.typeof "const char *[?]"
M.unsigned_int_array = ffi.typeof "unsigned int[?]"
M.size_t_array = ffi.typeof "size_t[?]"
M.int64_array = ffi.typeof "int64_t[?]"
M.int_array = ffi.typeof "int[?]"

---@type ffi.ctype* git_buf[1]
M.git_buf = ffi.typeof "git_buf[1]"

---@type ffi.ctype* git_config*[1]
M.git_config_double_pointer = ffi.typeof "git_config*[1]"
---@type ffi.ctype* git_config* pointer
M.git_config_pointer = ffi.typeof "git_config*"

---@type ffi.ctype* git_config_entry*[1]
M.git_config_entry_double_pointer = ffi.typeof "git_config_entry*[1]"

---@type ffi.ctype* git_config_iterator*[1]
M.git_config_iterator_double_pointer = ffi.typeof "git_config_iterator*[1]"

---@type ffi.ctype* git_checkout_options[1]
M.git_checkout_options = ffi.typeof "git_checkout_options[1]"

---@type ffi.ctype* git_oid[1]
M.git_oid = ffi.typeof "git_oid[1]"
---@type ffi.ctype* git_oid*
M.git_oid_pointer = ffi.typeof "git_oid*"

---@type ffi.ctype* git_strarray_readonly[1]
M.git_strarray_readonly = ffi.typeof "git_strarray_readonly[1]"
---@type ffi.ctype* git_strarray[1]
M.git_strarray = ffi.typeof "git_strarray[1]"

---@type ffi.ctype* git_annotated_commit **
M.git_annotated_commit_double_pointer = ffi.typeof "git_annotated_commit*[1]"
---@type ffi.ctype* git_annotated_commit *
M.git_annotated_commit_pointer = ffi.typeof "git_annotated_commit*"

---@type ffi.ctype* git_object **
M.git_object_double_pointer = ffi.typeof "git_object*[1]"
---@type ffi.ctype* git_object *
M.git_object_pointer = ffi.typeof "git_object*"

---@type ffi.ctype* git_blame **
M.git_blame_double_pointer = ffi.typeof "git_blame*[1]"
---@type ffi.ctype* git_blame*
M.git_blame_pointer = ffi.typeof "git_blame*"
---@type ffi.ctype* const git_blame_hunk *
M.git_blame_hunk_pointer = ffi.typeof "const git_blame_hunk*"
---@type ffi.ctype* git_blame_options [1]
M.git_blame_options = ffi.typeof "git_blame_options[1]"

---@type ffi.ctype* git_commit **
M.git_commit_double_pointer = ffi.typeof "git_commit*[1]"
---@type ffi.ctype* git_commit *
M.git_commit_pointer = ffi.typeof "git_commit*"
---@type ffi.ctype* git_commit * array
M.git_commit_pointer_array = ffi.typeof "git_commit*[?]"
---@type ffi.ctype* const git_commit **
M.git_commit_const_double_pointer = ffi.typeof "const git_commit**"

---@type ffi.ctype* git_blob **
M.git_blob_double_pointer = ffi.typeof "git_blob*[1]"
---@type ffi.ctype* git_blob *
M.git_blob_pointer = ffi.typeof "git_blob*"

---@type ffi.ctype* git_tree **
M.git_tree_double_pointer = ffi.typeof "git_tree*[1]"
---@type ffi.ctype* git_tree *
M.git_tree_pointer = ffi.typeof "git_tree*"

---@type ffi.ctype* git_tree_entry*[1]
M.git_tree_entry_double_pointer = ffi.typeof "git_tree_entry*[1]"
---@type ffi.ctype* git_tree_entry*
M.git_tree_entry_pointer = ffi.typeof "git_tree_entry*"

---@type ffi.ctype* git_rebase_options[1]
M.git_rebase_options = ffi.typeof "git_rebase_options[1]"

---@type ffi.ctype* git_apply_options[1]
M.git_apply_options = ffi.typeof "git_apply_options[1]"

---@type ffi.ctype* struct git_diff **
M.git_diff_double_pointer = ffi.typeof "git_diff*[1]"
---@type ffi.ctype* struct git_diff *
M.git_diff_pointer = ffi.typeof "git_diff*"

---@type ffi.ctype* struct git_diff_options [1]
M.git_diff_options = ffi.typeof "git_diff_options[1]"

---@type ffi.ctype* struct git_diff_find_options [1]
M.git_diff_find_options = ffi.typeof "git_diff_find_options[1]"

---@type ffi.ctype* struct git_diff_hunk *[1]
M.git_diff_hunk_double_pointer = ffi.typeof "const git_diff_hunk*[1]"

---@type ffi.ctype* const struct git_diff_line **out
M.git_diff_line_double_pointer = ffi.typeof "const git_diff_line*[1]"

---@type ffi.ctype* struct git_diff_stats *[1]
M.git_diff_stats_double_pointer = ffi.typeof "git_diff_stats*[1]"

---@type ffi.ctype* struct git_patch **
M.git_patch_double_pointer = ffi.typeof "git_patch*[1]"
---@type ffi.ctype* struct git_patch *
M.git_patch_pointer = ffi.typeof "git_patch*"

---@type ffi.ctype* git_rebase **
M.git_rebase_double_pointer = ffi.typeof "git_rebase*[1]"
---@type ffi.ctype* git_rebase *
M.git_rebase_pointer = ffi.typeof "git_rebase*"

---@type ffi.ctype* git_rebase_operation_double_pointer
M.git_rebase_operation_double_pointer = ffi.typeof "git_rebase_operation*[1]"
---@type ffi.ctype* git_rebase_operation struct pointer
M.git_rebase_operation_pointer = ffi.typeof "git_rebase_operation*"

---@type ffi.ctype* struct git_repository**
M.git_repository_double_pointer = ffi.typeof "git_repository*[1]"
---@type ffi.ctype* struct git_repository*
M.git_repository_pointer = ffi.typeof "git_repository*"

---@type ffi.ctype* struct git_reference*[1]
M.git_reference_double_pointer = ffi.typeof "git_reference*[1]"

---@type ffi.ctype* struct git_reference*
M.git_reference_pointer = ffi.typeof "git_reference*"

---@type ffi.ctype* struct git_remote**
M.git_remote_double_pointer = ffi.typeof "git_remote*[1]"
---@type ffi.ctype* struct git_remote*
M.git_remote_pointer = ffi.typeof "git_remote*"

---@type ffi.ctype* struct git_revwalk**
M.git_revwalk_double_pointer = ffi.typeof "git_revwalk*[1]"

---@type ffi.ctype* struct git_revwalk*
M.git_revwalk_pointer = ffi.typeof "git_revwalk*"

---@type ffi.ctype* git_signature **
M.git_signature_double_pointer = ffi.typeof "git_signature*[1]"
---@type ffi.ctype* git_signature *
M.git_signature_pointer = ffi.typeof "git_signature*"

---@type ffi.ctype* git_status_options[1]
M.git_status_options = ffi.typeof "git_status_options[1]"

---@type ffi.ctype* struct git_status_list*[1]
M.git_status_list_double_pointer = ffi.typeof "git_status_list*[1]"
---@type ffi.ctype* struct git_status_list*
M.git_status_list_pointer = ffi.typeof "git_status_list*"

---@type ffi.ctype* git_tag*[1]
M.git_tag_double_pointer = ffi.typeof "git_tag*[1]"
---@type ffi.ctype* git_tag*
M.git_tag_pointer = ffi.typeof "git_tag*"

---@type ffi.ctype* git_index**
M.git_index_double_pointer = ffi.typeof "git_index*[1]"
---@type ffi.ctype* git_index*
M.git_index_pointer = ffi.typeof "git_index*"

---@type ffi.ctype* git_index_iterator**
M.git_index_iterator_double_pointer = ffi.typeof "git_index_iterator*[1]"
---@type ffi.ctype* git_index_entry**
M.git_index_entry_double_pointer = ffi.typeof "git_index_entry*[1]"
---@type ffi.ctype* git_index_entry pointer array
M.git_index_entry_pointer_array = ffi.typeof "const git_index_entry*[?]"
---@type ffi.ctype* git_index_entry pointer
M.git_index_entry_pointer = ffi.typeof "const git_index_entry*"
---@type ffi.ctype* git_index_entry[1]
M.git_index_entry = ffi.typeof "git_index_entry[1]"

---@type ffi.ctype* struct git_branch_iterator *[1]
M.git_branch_iterator_double_pointer = ffi.typeof "git_branch_iterator *[1]"

-- ==========================
-- | libgit2 struct version |
-- ==========================

local _UI64_MAX = 0xffffffffffffffffULL

M.GIT_APPLY_OPTIONS_VERSION = 1
M.GIT_BLAME_OPTIONS_VERSION = 1
M.GIT_CHECKOUT_OPTIONS_VERSION = 1
M.GIT_DIFF_FIND_OPTIONS_VERSION = 1
M.GIT_DIFF_OPTIONS_VERSION = 1
M.GIT_FETCH_OPTIONS_VERSION = 1
M.GIT_MERGE_OPTIONS_VERSION = 1
M.GIT_PROXY_OPTIONS_VERSION = 1
M.GIT_REBASE_OPTIONS_VERSION = 1
M.GIT_REMOTE_CALLBACKS_VERSION = 1
M.GIT_STATUS_OPTIONS_VERSION = 1

M.GIT_REBASE_NO_OPERATION = _UI64_MAX

-- ================
-- | libgit2 enum |
-- ================

local POW = {
  2, -- 1 << 1
  4, -- 1 << 2
  8, -- 1 << 3
  16, -- 1 << 4
  32, -- 1 << 5
  64, -- 1 << 6
  0x80, -- 1 << 7
  0x100, -- 1 << 8
  0x200, -- 1 << 9
  0x400, -- 1 << 10
  0x800, -- 1 << 11
  0x1000, -- 1 << 12
  0x2000, -- 1 << 13
  0x4000, -- 1 << 14
  0x8000, -- 1 << 15
  0x10000, -- 1 << 16
  0x20000, -- 1 << 17
  0x40000, -- 1 << 18
  0x80000, -- 1 << 19
  0x100000, -- 1 << 20
  0x200000, -- 1 << 21
  0x400000, -- 1 << 22
  0x800000, -- 1 << 23
  0x1000000, -- 1 << 24
  0x2000000, -- 1 << 25
  0x4000000, -- 1 << 26
  0x8000000, -- 1 << 27
  0x10000000, -- 1 << 28
  0x20000000, -- 1 << 29
  0x40000000, -- 1 << 30
  0x80000000, -- 1 << 31
  0x100000000, -- 1 << 32
}

---@enum GIT_OPT
M.GIT_OPT = {
  GET_MWINDOW_SIZE = 0,
  SET_MWINDOW_SIZE = 1,
  GET_MWINDOW_MAPPED_LIMIT = 2,
  SET_MWINDOW_MAPPED_LIMIT = 3,
  GET_SEARCH_PATH = 4,
  SET_SEARCH_PATH = 5,
  SET_CACHE_OBJECT_LIMIT = 6,
  SET_CACHE_MAX_SIZE = 7,
  ENABLE_CACHING = 8,
  GET_CACHED_MEMORY = 9,
  GET_TEMPLATE_PATH = 10,
  SET_TEMPLATE_PATH = 11,
  SET_SSL_CERT_LOCATIONS = 12,
  SET_USER_AGENT = 13,
  ENABLE_STRICT_OBJECT_CREATION = 14,
  ENABLE_STRICT_SYMBOLIC_REF_CREATION = 15,
  SET_SSL_CIPHERS = 16,
  GET_USER_AGENT = 17,
  ENABLE_OFS_DELTA = 18,
  ENABLE_FSYNC_GITDIR = 19,
  GET_WINDOWS_SHAREMODE = 20,
  SET_WINDOWS_SHAREMODE = 21,
  ENABLE_STRICT_HASH_VERIFICATION = 22,
  SET_ALLOCATOR = 23,
  ENABLE_UNSAVED_INDEX_SAFETY = 24,
  GET_PACK_MAX_OBJECTS = 25,
  SET_PACK_MAX_OBJECTS = 26,
  DISABLE_PACK_KEEP_FILE_CHECKS = 27,
  ENABLE_HTTP_EXPECT_CONTINUE = 28,
  GET_MWINDOW_FILE_LIMIT = 29,
  SET_MWINDOW_FILE_LIMIT = 30,
  SET_ODB_PACKED_PRIORITY = 31,
  SET_ODB_LOOSE_PRIORITY = 32,
  GET_EXTENSIONS = 33,
  SET_EXTENSIONS = 34,
  GET_OWNER_VALIDATION = 35,
  SET_OWNER_VALIDATION = 36,
  GET_HOMEDIR = 37,
  SET_HOMEDIR = 38,
  SET_SERVER_CONNECT_TIMEOUT = 39,
  GET_SERVER_CONNECT_TIMEOUT = 40,
  SET_SERVER_TIMEOUT = 41,
  GET_SERVER_TIMEOUT = 42,
}

---@enum GIT_APPLY_LOCATION
M.GIT_APPLY_LOCATION = {
  WORKDIR = 0,
  INDEX = 1,
  BOTH = 2,
}

M.GIT_BLAME = {
  NORMAL = 0,
  TRACK_COPIES_SAME_FILE = 1, -- not yet implemented
  TRACK_COPIES_SAME_COMMIT_MOVES = 2, -- not yet implemented
  TRACK_COPIES_SAME_COMMIT_COPIES = 4, -- not yet implemented
  TRACK_COPIES_ANY_COMMIT_COPIES = 8, -- not yet implemented
  FIRST_PARENT = POW[4], -- (1<<4)
  USE_MAILMAP = POW[5], -- (1<<5)
  IGNORE_WHITESPACE = POW[6], -- (1<<6)
}

---@enum GIT_BRANCH
M.GIT_BRANCH = {
  LOCAL = 1,
  REMOTE = 2,
  ALL = 3, -- GIT_BRANCH_LOCAL|GIT_BRANCH_REMOTE,
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
  HIGHEST_LEVEL = -1,
}
---@enum GIT_ERROR
M.GIT_ERROR = {
  GIT_OK = 0, -- No error

  GIT_ERROR = -1, -- Generic error
  GIT_ENOTFOUND = -3, -- Requested object could not be found
  GIT_EEXISTS = -4, -- Object exists preventing operation
  GIT_EAMBIGUOUS = -5, -- More than one object matches
  GIT_EBUFS = -6, -- Output buffer too short to hold data
  --[[
  GIT_EUSER is a special error that is never generated by libgit2
  code.  You can return it from a callback (e.g to stop an iteration)
  to know that it was generated by the callback and not by libgit2.
  ]]
  --
  GIT_EUSER = -7,

  GIT_EBAREREPO = -8, -- Operation not allowed on bare repository
  GIT_EUNBORNBRANCH = -9, -- HEAD refers to branch with no commits
  GIT_EUNMERGED = -10, -- Merge in progress prevented operation
  GIT_ENONFASTFORWARD = -11, -- Reference was not fast-forwardable
  GIT_EINVALIDSPEC = -12, -- Name/ref spec was not in a valid format
  GIT_ECONFLICT = -13, -- Checkout conflicts prevented operation
  GIT_ELOCKED = -14, -- Lock file prevented operation
  GIT_EMODIFIED = -15, -- Reference value does not match expected
  GIT_EAUTH = -16, -- Authentication error
  GIT_ECERTIFICATE = -17, -- Server certificate is invalid
  GIT_EAPPLIED = -18, -- Patch/merge has already been applied
  GIT_EPEEL = -19, -- The requested peel operation is not possible
  GIT_EEOF = -20, -- Unexpected EOF
  GIT_EINVALID = -21, -- Invalid operation or input
  GIT_EUNCOMMITTED = -22, -- Uncommitted changes in index prevented operation
  GIT_EDIRECTORY = -23, -- The operation is not valid for a directory
  GIT_EMERGECONFLICT = -24, -- A merge conflict exists and cannot continue
  GIT_PASSTHROUGH = -30, -- A user-configured callback refused to act
  GIT_ITEROVER = -31, -- Signals end of iteration with iterator
  GIT_RETRY = -32, -- Internal only
  GIT_EMISMATCH = -33, -- Hashsum mismatch in object
  GIT_EINDEXDIRTY = -34, -- Unsaved changes in the index would be overwritten
  GIT_EAPPLYFAIL = -35, -- Patch application failed
  GIT_EOWNER = -36, -- The object is not owned by the current user
  GIT_TIMEOUT = -37, -- The operation timed out
}

---@enum GIT_INDEX_STAGE
M.GIT_INDEX_STAGE = {
  ANY = -1, -- Match any index stage.
  NORMAL = 0, -- A normal staged file in the index.
  ANCESTOR = 1, -- The ancestor side of a conflict.
  OURS = 2, -- The "ours" side of a conflict.
  THEIRS = 3, -- The "theirs" side of a conflict.
}

---@enum GIT_REFERENCE
M.GIT_REFERENCE = {
  INVALID = 0, -- Invalid reference
  DIRECT = 1, -- A reference that points at an object id
  SYMBOLIC = 2, -- A reference that points at another reference
  ALL = 3, -- Both GIT_REFERENCE_DIRECT | GIT_REFERENCE_SYMBOLIC
}

---@enum GIT_OBJECT
M.GIT_OBJECT = {
  ANY = -2, -- Object can be any of the following.
  INVALID = -1, -- Object is invalid.
  COMMIT = 1, -- A commit object.
  TREE = 2, -- A tree (directory listing) object.
  BLOB = 3, -- A file revision object.
  TAG = 4, -- An annotated tag object.
  OFS_DELTA = 6, -- A delta, base is given by an offset.
  REF_DELTA = 7, -- A delta, base is given by object id.
}

---@enum GIT_SORT
M.GIT_SORT = {
  NONE = 0, -- 0, default method from `git`: reverse chronological order
  TOPOLOGICAL = 1, -- 1 << 0, Sort the repository contents in topological order
  TIME = 2, -- 1 << 1, Sort the repository contents by commit time.
  REVERSE = 4, -- 1 << 2, Iterate through the repository contents in reverse order.
}

---@enum GIT_STATUS
M.GIT_STATUS = {
  CURRENT = 0,

  INDEX_NEW = 1, -- 1u << 0
  INDEX_MODIFIED = POW[1], -- 1u << 1
  INDEX_DELETED = POW[2], -- 1u << 2
  INDEX_RENAMED = POW[3], -- 1u << 3
  INDEX_TYPECHANGE = POW[4], -- 1u << 4

  WT_NEW = POW[7], -- 1u << 7
  WT_MODIFIED = POW[8], -- 1u << 8
  WT_DELETED = POW[9], -- 1u << 9
  WT_TYPECHANGE = POW[10], -- 1u << 10
  WT_RENAMED = POW[11], -- 1u << 11
  WT_UNREADABLE = POW[12], -- 1u << 12

  IGNORED = POW[14], -- 1u << 14
  CONFLICTED = POW[15], -- 1u << 15
}

---@enum GIT_STATUS_SHOW
M.GIT_STATUS_SHOW = {
  INDEX_AND_WORKDIR = 0,
  INDEX_ONLY = 1,
  WORKDIR_ONLY = 2,
}

---@enum GIT_STATUS_OPT
M.GIT_STATUS_OPT = {
  INCLUDE_UNTRACKED = 1, -- (1u << 0),
  INCLUDE_IGNORED = POW[1], -- (1u << 1),
  INCLUDE_UNMODIFIED = POW[2], -- (1u << 2),
  EXCLUDE_SUBMODULES = POW[3], -- (1u << 3),
  RECURSE_UNTRACKED_DIRS = POW[4], -- (1u << 4),
  DISABLE_PATHSPEC_MATCH = POW[5], -- (1u << 5),
  RECURSE_IGNORED_DIRS = POW[6], -- (1u << 6),
  RENAMES_HEAD_TO_INDEX = POW[7], -- (1u << 7),
  RENAMES_INDEX_TO_WORKDIR = POW[8], -- (1u << 8),
  SORT_CASE_SENSITIVELY = POW[9], -- (1u << 9),
  SORT_CASE_INSENSITIVELY = POW[10], -- (1u << 10),
  RENAMES_FROM_REWRITES = POW[11], -- (1u << 11),
  NO_REFRESH = POW[12], -- (1u << 12),
  UPDATE_INDEX = POW[13], -- (1u << 13),
  INCLUDE_UNREADABLE = POW[14], -- (1u << 14),
  INCLUDE_UNREADABLE_AS_UNTRACKED = POW[15], -- (1u << 15)
}

---@enum GIT_DELTA
M.GIT_DELTA = {
  UNMODIFIED = 0, -- no changes
  ADDED = 1, -- entry does not exist in old version
  DELETED = 2, -- entry does not exist in new version
  MODIFIED = 3, -- entry content changed between old and new
  RENAMED = 4, -- entry was renamed between old and new
  COPIED = 5, -- entry was copied from another old entry
  IGNORED = 6, -- entry is ignored item in workdir
  UNTRACKED = 7, -- entry is untracked item in workdir
  TYPECHANGE = 8, -- type of entry changed between old and new
  UNREADABLE = 9, -- entry is unreadable
  CONFLICTED = 10, -- entry in the index is conflicted
}

---@enum GIT_REPOSITORY_OPEN
M.GIT_REPOSITORY_OPEN = {
  NO_SEARCH = 1,

  --  Unless this flag is set, open will not continue searching across
  -- filesystem boundaries (i.e. when `st_dev` changes from the `stat`
  -- system call).  For example, searching in a user's home directory at
  -- "/home/user/source/" will not return "/.git/" as the found repo if
  -- "/" is a different filesystem than "/home".
  CROSS_FS = 2,

  -- Open repository as a bare repo regardless of core.bare config, and
  -- defer loading config file for faster setup.
  -- Unlike `git_repository_open_bare`, this can follow gitlinks.
  BARE = 4,

  NO_DOTGIT = 8,
  FROM_ENV = 16,
}

---@enum GIT_DIFF_FORMAT
M.GIT_DIFF_FORMAT = {
  PATCH = 1, -- full git diff
  PATCH_HEADER = 2, -- just the file headers of patch
  RAW = 3, -- like git diff --raw
  NAME_ONLY = 4, -- like git diff --name-only
  NAME_STATUS = 5, -- like git diff --name-status
  PATCH_ID = 6, -- git diff as used by git patch-id
}

---@enum GIT_DIFF
M.GIT_DIFF = {
  NORMAL = 0, --0: Normal diff, the default
  REVERSE = 1, --(1 << 0): Reverse the sides of the diff
  INCLUDE_IGNORED = 2, --(1 << 1): Include ignored files in the diff
  RECURSE_IGNORED_DIRS = 4, --(1 << 2): adds files under the ignored directory as IGNORED entries
  INCLUDE_UNTRACKED = 8, --(1 << 3): Include untracked files in the diff
  RECURSE_UNTRACKED_DIRS = 0x10, --(1 << 4): adds files under untracked directories as UNTRACKED entries
  INCLUDE_UNMODIFIED = 0x20, --(1 << 5): include unmodified files in the diff
  -- a type change between files will be converted into a
  -- DELETED record for the old and an ADDED record for the new; this
  -- options enabled the generation of TYPECHANGE delta records
  INCLUDE_TYPECHANGE = 0x40, --(1 << 6)
  -- Even with GIT_DIFF_INCLUDE_TYPECHANGE, blob->tree changes still
  -- generally show as a DELETED blob.  This flag tries to correctly
  -- label blob->tree transitions as TYPECHANGE records with new_file's
  -- mode set to tree.  Note: the tree SHA will not be available.
  INCLUDE_TYPECHANGE_TREES = 0x80, --(1 << 7)
  IGNORE_FILEMODE = 0x100, --(1u << 8): Ignore file mode changes
  IGNORE_SUBMODULES = 0x200, --(1u << 9): Treat all submodules as unmodified
  IGNORE_CASE = 0x400, --(1u << 10): case insensitive for filename comparisons
  INCLUDE_CASECHANGE = 0x800, --(1u << 11): combined with `IGNORE_CASE` to specify that a file that has changed case will be returned as an add/delete pair.

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
  UPDATE_INDEX = 0x8000, --(1u << 15)
  INCLUDE_UNREADABLE = 0x10000, -- 1u << 16): Include unreadable files in the diff
  INCLUDE_UNREADABLE_AS_UNTRACKED = 0x20000, --(1u << 17): Include unreadable files as UNTRACKED

  -- Options controlling how output will be generated

  -- Use a heuristic that takes indentation and whitespace into account
  -- which generally can produce better diffs when dealing with ambiguous
  -- diff hunks.
  INDENT_HEURISTIC = 0x40000, --(1u << 18)
  IGNORE_BLANK_LINES = 0x80000, --(1u << 19): Ignore blank lines
  FORCE_TEXT = 0x100000, --(1u << 20): Treat all files as text, disabling binary attributes & detection
  FORCE_BINARY = 0x200000, --(1u << 21): Treat all files as binary, disabling text diffs
  IGNORE_WHITESPACE = 0x400000, --(1u << 22): Ignore all whitespaces
  IGNORE_WHITESPACE_CHANGE = 0x800000, --(1u << 23): Ignore changes in amount of whitespace
  IGNORE_WHITESPACE_EOL = 0x1000000, --(1u << 24): Ignore whitespace at end of line

  -- When generating patch text, include the content of untracked files.
  -- This automatically turns on GIT_DIFF_INCLUDE_UNTRACKED but
  -- it does not turn on GIT_DIFF_RECURSE_UNTRACKED_DIRS.
  -- Add that flag if you want the content of every single UNTRACKED file.
  SHOW_UNTRACKED_CONTENT = 0x2000000, --(1u << 25)

  -- When generating output, include the names of unmodified files if
  -- they are included in the git_diff. Normally these are skipped in
  -- the formats that list files (e.g. name-only, name-status, raw).
  -- Even with this, these will not be included in patch format.
  SHOW_UNMODIFIED = 0x4000000, --(1u << 26)

  PATIENCE = 0x10000000, --(1u << 28): Use the "patience diff" algorithm
  MINIMAL = 0x20000000, --(1u << 29): Take extra time to find minimal diff
  -- Include the necessary deflate / delta information so that `git-apply`
  -- can apply given diff information to binary files.
  SHOW_BINARY = 0x40000000, --(1u << 30)
}

---@enum GIT_DIFF_FIND
M.GIT_DIFF_FIND = {
  FIND_BY_CONFIG = 0, -- Obey `diff.renames
  FIND_RENAMES = 1, -- (1u << 0): Look for renames? (`--find-renames`)
  FIND_RENAMES_FROM_REWRITES = 2, -- (1u << 1)
  FIND_COPIES = 4, -- (1u << 2)
  FIND_COPIES_FROM_UNMODIFIED = 8, -- (1u << 3)
  FIND_REWRITES = POW[4], -- (1u << 4)
  BREAK_REWRITES = POW[5], -- (1u << 5)
  FIND_AND_BREAK_REWRITES = 48, -- (GIT_DIFF_FIND_REWRITES | GIT_DIFF_BREAK_REWRITES)
  FIND_FOR_UNTRACKED = POW[6], -- (1u << 6)
  FIND_ALL = 0xff, -- (0x0ff) Turn on all finding features.
  FIND_IGNORE_LEADING_WHITESPACE = 0,
  FIND_IGNORE_WHITESPACE = POW[12], -- (1u << 12),
  FIND_DONT_IGNORE_WHITESPACE = POW[13], -- (1u << 13),
  FIND_EXACT_MATCH_ONLY = POW[14], -- (1u << 14),
  BREAK_REWRITES_FOR_RENAMES_ONLY = POW[15], -- (1u << 15),
  FIND_REMOVE_UNMODIFIED = POW[16], -- (1u << 16)
}

---@enum GIT_SUBMODULE
M.GIT_SUBMODULE = {
  IGNORE_UNSPECIFIED = -1, -- use the submodule's configuration
  IGNORE_NONE = 1, -- any change or untracked == dirty
  IGNORE_UNTRACKED = 2, -- dirty if tracked files change
  IGNORE_DIRTY = 3, -- only dirty if HEAD moved
  IGNORE_ALL = 4, -- never dirty
}

---@enum GIT_DIFF_LINE
M.GIT_DIFF_LINE = {
  CONTEXT = " ",
  ADDITION = "+",
  DELETION = "-",
  CONTEXT_EOFNL = "=", --Both files have no LF at end
  ADD_EOFNL = ">", --Old has no LF at end, new does
  DEL_EOFNL = "<", --Old has LF at end, new does not
  FILE_HDR = "F",
  HUNK_HDR = "H",
  BINARY = "B", -- For "Binary files x and y differ"
}

---@enum GIT_REBASE_OPERATION
M.GIT_REBASE_OPERATION = {
  PICK = 0,
  REWORD = 1,
  EDIT = 2,
  SQUASH = 3,
  FIXUP = 4,
  EXEC = 5,
}

---@enum GIT_CHECKOUT
M.GIT_CHECKOUT = {
  NONE = 0, -- default is a dry run, no actual updates
  SAFE = 1, --(1u << 0): Allow safe updates that cannot overwrite uncommitted data.
  FORCE = 2, --(1u << 1): Allow all updates to force working directory to look like index.
  RECREATE_MISSING = 4, --(1u << 2): Allow checkout to recreate missing files.
  ALLOW_CONFLICTS = POW[4], --(1u << 4): Allow checkout to make safe updates even if conflicts are found.
  REMOVE_UNTRACKED = POW[5], --(1u << 5): Remove untracked files not in index (that are not ignored.
  REMOVE_IGNORED = POW[6], --(1u << 6): Remove ignored files not in index */
  UPDATE_ONLY = POW[7], --(1u << 7) Only update existing files, don't create new ones.
  DONT_UPDATE_INDEX = POW[8], --(1u << 8) Normally checkout updates index entries as it goes; this stops that.
  NO_REFRESH = POW[9], --(1u << 9) Don't refresh index/config/etc before doing checkout.
  SKIP_UNMERGED = POW[10], -- (1u << 10) Allow checkout to skip unmerged files,
  USE_OURS = POW[11], --(1u << 11) For unmerged files, checkout stage 2 from index,
  USE_THEIRS = POW[12], -- (1u << 12) For unmerged files, checkout stage 3 from index */
  DISABLE_PATHSPEC_MATCH = POW[13], -- (1u << 13) Treat pathspec as simple list of exact match file paths,
  SKIP_LOCKED_DIRECTORIES = POW[18], --(1u << 18) Ignore directories in use, they will be left empty
  DONT_OVERWRITE_IGNORED = POW[19], --(1u << 19) Don't overwrite ignored files that exist in the checkout target
  CONFLICT_STYLE_MERGE = POW[20], --(1u << 20) Write normal merge files for conflicts
  CONFLICT_STYLE_DIFF3 = POW[21], --(1u << 21) Include common ancestor data in diff3 format files for conflicts
  DONT_REMOVE_EXISTING = POW[22], --(1u << 22) Don't overwrite existing files or folders
  DONT_WRITE_INDEX = POW[23], --(1u << 23) Normally checkout writes the index upon completion; this prevents that.
  DRY_RUN = POW[24], --(1u << 24),
  CONFLICT_STYLE_ZDIFF3 = POW[25], --(1u << 25) Include common ancestor data in zdiff3 format for conflicts.
  --(NOT IMPLEMENTED)
  UPDATE_SUBMODULES = POW[16], --(1u << 16) Recursively checkout submodules with same options
  UPDATE_SUBMODULES_IF_CHANGED = POW[17], --(1u << 17) Recursively checkout submodules if HEAD moved in super repo
}

---@enum GIT_MERGE
M.GIT_MERGE = {
  FIND_RENAMES = 1, --(1 << 0): Detect renames that occur between the common ancestor and the "ours"
  FAIL_ON_CONFLICT = POW[1], --(1 << 1): If a conflict occurs, exit immediately
  SKIP_REUC = POW[2], --(1 << 2): Do not write the REUC extension on the generated index
  NO_RECURSIVE = POW[3], --(1 << 3): This flag provides a similar merge base to `git-merge-resolve`.
  VIRTUAL_BASE = POW[4], --(1 << 4): Treat this merge as if it is to produce the virtual base of recursive.
}

-- Inits helper

local NULL = ffi.cast("void*", nil)

M.GIT_APPLY_OPTIONS_INIT = { { M.GIT_APPLY_OPTIONS_VERSION } }
M.GIT_BLAME_OPTIONS_INIT = { { M.GIT_BLAME_OPTIONS_VERSION } }
M.GIT_STATUS_OPTIONS_INIT = { { M.GIT_STATUS_OPTIONS_VERSION } }
M.GIT_DIFF_OPTIONS_INIT = {
  {
    M.GIT_STATUS_OPTIONS_VERSION,
    0,
    M.GIT_SUBMODULE.IGNORE_UNSPECIFIED,
    { NULL, 0 },
    NULL,
    NULL,
    NULL,
    3,
  },
}
M.GIT_DIFF_FIND_OPTIONS_INIT = { { M.GIT_DIFF_FIND_OPTIONS_VERSION } }
M.GIT_CHECKOUT_OPTIONS_INIT = { { M.GIT_CHECKOUT_OPTIONS_VERSION, M.GIT_CHECKOUT.SAFE } }
M.GIT_MERGE_OPTIONS_INIT = { { M.GIT_MERGE_OPTIONS_VERSION, M.GIT_MERGE.FIND_RENAMES } }
M.GIT_REBASE_OPTIONS_INIT = {
  {
    M.GIT_REBASE_OPTIONS_VERSION,
    0,
    0,
    NULL,
    M.GIT_MERGE_OPTIONS_INIT[1],
    M.GIT_CHECKOUT_OPTIONS_INIT[1],
    NULL,
    NULL,
  },
}

return M
