# Interactive Rebase

Fugit2 provides interactive rebase through libgit2's native rebase API via LuaJIT FFI — no shell subprocess calls.

## Opening the Rebase Menu

From the status window (`:Fugit2`), press `r` to open the rebase menu.

## Rebase Menu Actions

| Key | Action | Description |
|-----|--------|-------------|
| `i` | Rebase onto upstream | Interactively rebase the current branch onto its configured upstream. |
| `e` | Rebase onto another branch | Open a branch picker, then interactively rebase onto the chosen branch. |

If no upstream is configured for the current branch, pressing `i` shows a warning and does nothing.

## Interactive Rebase UI

After selecting a target, the rebase view opens showing all commits to be replayed. Each commit can be assigned an action before the rebase begins.

### Commit Actions

| Key | Action | Behavior |
|-----|--------|----------|
| `p` | Pick | Apply the commit as-is (default). |
| `r` / `w` | Reword | Apply the commit with a modified message. |
| `e` | Edit | Apply the commit (edit is noted; execution continues). |
| `s` | Squash | Meld into the previous commit, combining messages. |
| `f` | Fixup | Meld into the previous commit, discarding this message. |
| `d` / `x` | Drop | Skip this commit entirely. |
| `b` | Break | Insert a pause point at this position. |
| `gj` / `<C-j>` | Move down | Move the commit down in the list. |
| `gk` / `<C-k>` | Move up | Move the commit up in the list. |
| `<Enter>` | Start rebase | Begin executing with the current action assignments. |
| `q` / `<Esc>` | Abort | Close the rebase view without applying any changes. |

### After Starting

Once `<Enter>` is pressed, the rebase executes automatically. If conflicts are detected, a prompt appears asking whether to open the diff view for resolution. After resolving conflicts, return to the rebase view and press `<Enter>` to continue.

On completion, the status view refreshes to show the new HEAD.

---

## Technical Details

This section covers the implementation architecture for contributors and maintainers.

### Files Changed

| File | Role |
|------|------|
| `lua/fugit2/core/libgit2.lua` | FFI C declarations for rebase API |
| `lua/fugit2/core/git2.lua` | `Rebase` class and `Repository` Lua wrapper methods |
| `lua/fugit2/core/git_rebase_helper.lua` | Rebase action enum and helper utilities |
| `lua/fugit2/view/git_rebase.lua` | Interactive rebase UI view |
| `lua/fugit2/view/git_status.lua` | Menu integration (`r` key, `REBASE` menu) |

### FFI Layer (`libgit2.lua`)

#### C Declarations

Structs declared inside the `ffi.cdef` block:

```c
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

typedef struct {
  git_repository *repo;
  git_rebase_options options;
  unsigned int type;
  char *state_path;
  git_str state_filename;
  unsigned int head_detached:1, inmemory:1, quiet:1, started:1;
  git_rebase_operation_array_t operations;
  size_t current;
  git_index *index;
  git_commit *last_commit;
  git_oid orig_head_id;
  char *orig_head_name;
  git_oid onto_id;
  char *onto_name;
} git_rebase;
```

Functions declared inside the `ffi.cdef` block:

```c
int git_rebase_init(git_rebase **out, git_repository *repo,
    const git_annotated_commit *branch, const git_annotated_commit *upstream,
    const git_annotated_commit *onto, const git_rebase_options *opts);
int git_rebase_open(git_rebase **out, git_repository *repo,
    const git_rebase_options *opts);
const char * git_rebase_orig_head_name(git_rebase *rebase);
const git_oid * git_rebase_orig_head_id(git_rebase *rebase);
const char * git_rebase_onto_name(git_rebase *rebase);
const git_oid * git_rebase_onto_id(git_rebase *rebase);
size_t git_rebase_operation_entrycount(git_rebase *rebase);
size_t git_rebase_operation_current(git_rebase *rebase);
git_rebase_operation * git_rebase_operation_byindex(git_rebase *rebase, size_t idx);
int git_rebase_inmemory_index(git_index **index, git_rebase *rebase);
int git_rebase_next(git_rebase_operation **operation, git_rebase *rebase);
int git_rebase_commit(git_oid *id, git_rebase *rebase,
    const git_signature *author, const git_signature *committer,
    const char *message_encoding, const char *message);
int git_rebase_abort(git_rebase *rebase);
int git_rebase_finish(git_rebase *rebase, const git_signature *signature);
void git_rebase_free(git_rebase *rebase);
```

#### Enum

```lua
---@enum GIT_REBASE_OPERATION
M.GIT_REBASE_OPERATION = {
  PICK   = 0,
  REWORD = 1,
  EDIT   = 2,
  SQUASH = 3,
  FIXUP  = 4,
  EXEC   = 5,
}
```

DROP is not a libgit2 native operation. Fugit2 maps it to `EXEC` with a nil exec string, then handles it via `Rebase:skip()` at execution time.

#### Init Table

```lua
M.GIT_REBASE_OPTIONS_VERSION = 1
M.GIT_REBASE_OPTIONS_INIT = {
  {
    M.GIT_REBASE_OPTIONS_VERSION,
    0,     -- quiet
    0,     -- inmemory (set to 1 at runtime for new rebases)
    NULL,  -- rewrite_notes_ref
    M.GIT_MERGE_OPTIONS_INIT[1],
    M.GIT_CHECKOUT_OPTIONS_INIT[1],
    NULL,  -- commit_create_cb
    NULL,  -- reserved
  },
}
```

### `Rebase` Class (`git2.lua`)

The `Rebase` class wraps a `git_rebase*` pointer with `ffi.gc(rebase.rebase, libgit2_C.git_rebase_free)` for automatic cleanup.

#### Key Methods

| Method | Description |
|--------|-------------|
| `next()` | Advances to the next operation; returns `(GitRebaseOperation?, GIT_ERROR)`. Returns `GIT_ITEROVER` when all operations are exhausted. |
| `skip()` | Directly increments the rebase's internal `current` counter without calling `git_rebase_next`. Used for DROP operations. libgit2 has no native skip API. |
| `commit(author, committer, message)` | Creates a commit from the current operation's index state. Works for both in-memory and on-disk modes. |
| `amend(author, committer, message)` | Melds the current operation into the previous commit. In-memory only — delegates to `_rebase_amend_inmemory`. On-disk amend returns an error. |
| `finish(signature)` | Calls `git_rebase_finish`. For in-memory rebases, the caller must then update HEAD and checkout. |
| `abort()` | Calls `git_rebase_abort`, resetting the repository to its pre-rebase state. |
| `inmemory_index()` | Returns the in-memory `GitIndex` produced by the last `next()` call. Used for conflict detection and diff display. |
| `is_inmemory()` | Returns `true` if the rebase's `inmemory` bit is set. |
| `noperations()` | Returns the total number of operations in the rebase. |

#### In-Memory Amend (`_rebase_amend_inmemory`)

Used for SQUASH and FIXUP. libgit2 exposes no `git_rebase_amend` function, so this is a custom implementation:

1. Retrieves `rebase["index"]` and `rebase["last_commit"]` directly from the FFI struct.
2. Checks for unresolved conflicts via `git_index_has_conflicts`.
3. Writes the in-memory index tree to the repository with `git_index_write_tree_to`.
4. Calls `git_commit_amend` on the previous commit using the new tree.
5. Updates `rebase["last_commit"]` to the amended commit pointer (freeing the old one).

The parent tree equality check (`git_oid_equal` on parent vs new tree) returns `GIT_EAPPLIED` if the patch was already applied — consistent with `git_rebase_commit` behavior.

### Repository Methods (`git2.lua`)

#### `rebase_init(branch, upstream, onto, opts)`

- Allocates `git_rebase_options[1]` from `GIT_REBASE_OPTIONS_INIT`
- If `opts.inmemory` is truthy, sets `rebase_opts[0].inmemory = 1`
- Calls `git_rebase_init(out, repo, branch.commit, upstream.commit, onto.commit, opts)`
- All three annotated commit args may be `nil` (passed as NULL to libgit2)
- Returns `Rebase.new(git_rebase[0]), 0` on success

#### `rebase_open()`

- Allocates options from `GIT_REBASE_OPTIONS_INIT` with `inmemory = 0`
- Calls `git_rebase_open` to resume an existing on-disk rebase from `.git/rebase-merge/`
- Returns `Rebase.new(git_rebase[0]), 0` on success

### Rebase View (`git_rebase.lua`)

#### Constructor (`RebaseView:init`)

Three initialization paths, all set `self._git.rebase` and `self._git.rebase_info`:

| Config provided | Path | `inmemory` |
|-----------------|------|------------|
| `ref_config` | `_init_rebase_ref` | `true` |
| `revspec_config` | `_init_rebase_revspec` | `true` |
| Neither | `repo:rebase_open()` | `false` |

Both `_init_rebase_ref` and `_init_rebase_revspec` call `repo:rebase_init(..., { inmemory = true })`. On-disk path calls `repo:rebase_open()`.

`rebase_info` is a `Fugit2UIGitRebaseInfo` table: `{ branch, upstream, onto: GitObjectId, onto_name: string }`.

#### Execution Lifecycle

```
<Enter> in commit list
  -> rebase_start()
       remaps operations and OIDs from UI actions/oids tables
       replaces commit-list keymaps
       calls rebase_continue()

rebase_continue()         -- loop: next/skip -> commit/amend
  |
  +-- GIT_ITEROVER -----> rebase_finish()
  |                          git_rebase_finish()
  |                          [in-memory only]:
  |                            update_head_for_commit(last_commit_id)
  |                            checkout_head(SAFE | RECREATE_MISSING)
  |                          on_complete callback -> status refresh
  |
  +-- GIT_EUNMERGED ----> rebase_has_conflicts(commit_idx, oid)
  |                          marks commit as CONFLICT in UI
  |                          shows resolve confirm popup
  |                          on yes: opens GitDiff with rebase index
  |                          on BufEnter return: checks conflicts cleared
  |                          next <Enter> -> rebase_continue() resumes
  |
  +-- other error ------> rebase_abort()
                             git_rebase_abort()
                             unmounts view
```

#### In-Memory Finish Sequence

After `git_rebase_finish`, two extra steps are required because the working directory was untouched during the in-memory replay:

1. **Update HEAD ref**: `repo:update_head_for_commit(last_commit_id, summary, "rebase: ")` — moves `HEAD` to the final rebased commit.
2. **Checkout HEAD**: `repo:checkout_head(SAFE | ALLOW_CONFLICTS | RECREATE_MISSING)` — synchronizes the working directory with the new commit tree. `RECREATE_MISSING` ensures files added by rebased commits appear on disk. `SAFE` preserves locally modified files (does not overwrite them).

On-disk rebases skip both steps — libgit2 updates the working directory as each operation is applied.

#### `on_complete` Callback

`RebaseView:on_complete(callback)` stores a single `fun()` in `self._on_complete`. It is called via `vim.schedule` from `rebase_finish` after unmounting, allowing the parent (status view) to refresh asynchronously without a re-entrancy hazard.

Only one callback is stored. Calling `on_complete` twice replaces the first registration.

### Status View Integration (`git_status.lua`)

Follows the same 5-step menu pattern as all other menus:

1. **Enum**: `REBASE = 7` in the `Menu` table
2. **Data**: `_init_menus` elseif branch with two actions (`i` — upstream, `e` — pick branch)
3. **Wiring**: `_init_rebase_menu()` registers `on_submit` dispatcher:
   - `i`: reads `self._git.upstream.name`, creates `RebaseView` with `revspec_config = { upstream = name }`, registers `on_complete` to call `self:update_then_render()`
   - `e`: opens `GitPick(BRANCH_LOCAL_REMOTE)`, on submit creates `RebaseView` with the chosen ref
4. **Dispatch table**: `MENU_INITS[Menu.REBASE] = GitStatus._init_rebase_menu`
5. **Keybinding**: `file_tree:map("n", "r", self:_menu_handlers(Menu.REBASE), map_options)`

The menu is lazily constructed on first `r` keypress and cached in `self._menus[7]`.

### Data Flow

```
r keypress
  -> _menu_handlers closure
    -> lazy _init_rebase_menu() -> cached
    -> menu:mount()

i selection (rebase onto upstream):
  -> RebaseView(ns_id, repo, nil, { upstream = upstream.name })
  -> view:on_complete(-> status:update_then_render())
  -> view:mount()

e selection (pick branch):
  -> GitPick(BRANCH_LOCAL_REMOTE):mount()
  -> on_submit(ref):
       RebaseView(ns_id, repo, nil, { upstream = ref })
       view:on_complete(-> status:update_then_render())
       view:mount()

RebaseView constructor:
  _init_rebase_revspec(repo, nil, upstream, nil)
    -> repo:annotated_commit_from_revspec(upstream)
    -> repo:rebase_init(branch, upstream, nil, { inmemory = true })
    -> _init_rebase_info() -> rebase_info table
  load commits from walker
  build commit list UI

<Enter> to start:
  rebase_start()
    reorder operations per UI actions
    rebase_continue() loop

rebase_continue():
  DROP  -> rebase:skip()   (direct struct manipulation)
  PICK/REWORD/EDIT -> rebase:next() + rebase:commit()
  SQUASH/FIXUP     -> rebase:next() + rebase:amend()
    -> GIT_ITEROVER  -> rebase_finish()
    -> GIT_EUNMERGED -> rebase_has_conflicts()
    -> error         -> rebase_abort()

rebase_finish() [in-memory]:
  git_rebase_finish(signature)
  repo:update_head_for_commit(last_commit_id, ...)
  repo:checkout_head(SAFE | RECREATE_MISSING)
  vim.schedule(on_complete)
    -> status:update_then_render()
```

### Error Handling

Follows the codebase convention:

- All FFI calls return integer error codes (0 = success)
- `notifier.error(message, err_code)` on failure; `notifier.info` on success
- `GIT_EUNMERGED` is a recoverable state — the view stays open for conflict resolution
- `GIT_ITEROVER` signals normal completion — triggers `rebase_finish`
- Any other non-zero error triggers `rebase_abort` and unmounts the view
- `git2.error_last()` is not used (consistent with the rest of the codebase)

### Design Decisions & Risks

1. **In-memory by default for new rebases**: `_init_rebase_ref` and `_init_rebase_revspec` both set `inmemory = true`. The working directory is untouched until `rebase_finish` explicitly calls `checkout_head`. This means a crash or abort during rebase leaves the working directory in its original state, with no `.git/rebase-merge/` debris.

2. **Manual `skip()` for DROP**: libgit2 has no `git_rebase_skip` function. DROP is implemented by directly writing `c_rebase["current"]` and `c_rebase["started"]` — the same fields that `git_rebase_next` advances internally. This relies on the internal struct layout declared in the FFI cdef. If libgit2 changes this layout in a future version, `skip()` will need to be updated.

3. **On-disk amend not implemented**: `Rebase:amend` returns an error for on-disk rebases. On-disk SQUASH/FIXUP operations are therefore unsupported when reopening an existing rebase. In practice, the on-disk path (`rebase_open`) is reached only when a previous rebase was interrupted — and reordering/squashing in that context is not supported by the UI anyway.

4. **`rebase["last_commit"]` ownership**: In `_rebase_amend_inmemory`, the old `last_commit` pointer is freed with `git_commit_free` before the new amended commit is stored. The new commit is stored as a raw `ffi.cdata*` (not a managed `Commit` object), matching the struct's expected ownership model. Never store a `Commit` Lua object into `rebase["last_commit"]` — the GC finalizer would double-free the pointer.

5. **`RECREATE_MISSING` in checkout**: After in-memory rebase, `GIT_CHECKOUT.RECREATE_MISSING` is required to materialize files that exist in the new HEAD tree but are absent from the working directory (e.g., files added by rebased commits that were not in the original working tree). Without it, those files would be missing on disk despite being committed.

6. **`vim.schedule` for `on_complete`**: The callback is deferred via `vim.schedule` rather than called directly from `rebase_finish`. This prevents re-entrancy: `rebase_finish` calls `self:unmount()` first, which tears down NUI buffers and windows; calling the parent's `update_then_render()` synchronously during teardown would attempt to render into a partially-unmounted layout.

### Testing

Tests live in two spec files:

**`spec/fugit2/core/rebase_spec.lua`** — Repository and `Rebase` API tests using a temporary git repo:

| Test | Coverage |
|------|----------|
| `rebase_init` with `inmemory=true` | Returns `Rebase`, `is_inmemory()` is true |
| `noperations()` | One operation when rebasing HEAD onto HEAD~1 |
| `onto_name()` | Non-nil onto name after init |
| `inmemory_index()` after `next()` | Returns a valid `GitIndex` |
| In-memory finish + `checkout_head` | New file appears on disk after `RECREATE_MISSING` checkout |
| In-memory finish + `SAFE` checkout | Existing tracked files are not overwritten |
| `rebase_init` with `inmemory=false` | `is_inmemory()` is false |

**`spec/fugit2/view/git_rebase_spec.lua`** — Unit tests for the `on_complete` callback mechanism (no repo or NUI required):

| Test | Coverage |
|------|----------|
| Callback stored after `on_complete` | `_on_complete` is non-nil |
| Callback invoked on completion | `called = true` after `fire_complete()` |
| No error without callback | `fire_complete()` is safe when `_on_complete` is nil |
| Second registration replaces first | Only the latest callback is invoked |

Run tests with:

```bash
luarocks test --local -- --config-file=nlua.busted spec/fugit2/core/rebase_spec.lua
luarocks test --local -- --config-file=nlua.busted spec/fugit2/view/git_rebase_spec.lua
```
