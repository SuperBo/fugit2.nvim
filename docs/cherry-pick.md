# Cherry Pick

Fugit2 provides cherry-pick support through libgit2's native API — no shell subprocess calls.

## Opening the Cherry Pick Menu

From the status window (`:Fugit2`), press `A` to open the cherry pick menu.

## Cherry Pick Menu Actions

| Key | Action | Description |
|-----|--------|-------------|
| `A` | Pick commit | Open the commit graph to select a commit and apply it to HEAD. |

## Usage

1. Press `A` in the status window to open the cherry pick menu.
2. Press `A` again to open the commit graph picker.
3. Navigate to the desired commit with `j`/`k` and press `<Enter>` or `<Space>` to confirm.
4. The commit is applied in-memory and a new commit is created on HEAD immediately.

## Standalone Command

Cherry-pick is also available as a standalone command that opens the commit graph picker directly:

```vim
:Fugit2CherryPick
```

---

## Technical Details

This section covers the implementation architecture for contributors and maintainers.

### Files Changed

| File | Role |
|------|------|
| `lua/fugit2/core/libgit2.lua` | FFI C declarations for cherry-pick API |
| `lua/fugit2/core/git2.lua` | `Repository:cherry_pick()` Lua wrapper method |
| `lua/fugit2/view/git_status.lua` | Menu integration (`A` key, `CHERRY_PICK` menu) |
| `lua/fugit2/init.lua` | `git_cherry_pick` command handler |
| `plugin/fugit2.lua` | `:Fugit2CherryPick` user command registration |

### FFI Layer (`libgit2.lua`)

#### C Declarations

Added inside the `ffi.cdef` block:

```c
typedef struct git_cherrypick_options {
  unsigned int version;
  unsigned int mainline;
  git_merge_options merge_opts;
  git_checkout_options checkout_opts;
} git_cherrypick_options;

int git_cherrypick_options_init(git_cherrypick_options *opts, unsigned int version);
int git_cherrypick_commit(git_index **out, git_repository *repo,
    git_commit *cherrypick_commit, git_commit *our_commit,
    unsigned int mainline, const git_merge_options *merge_options);
```

### Repository Method (`git2.lua`)

```lua
function Repository:cherry_pick(oid)
```

In-memory flow (no working directory or index changes):

1. Look up the commit to cherry-pick via `self:commit_lookup(oid)`
2. Look up the current HEAD commit via `self:head_commit()`
3. Call `git_cherrypick_commit` — computes the cherry-pick result and returns an in-memory index
4. Check `git_index_has_conflicts` — return `GIT_EUNMERGED` on conflict
5. Write the result tree with `git_index_write_tree_to`
6. Create a commit via `git_commit_create` with the original commit's author and message, HEAD as parent, updating `HEAD`
7. Return the integer error code (0 = success)

The working directory and the repository index are never touched.

### Status View Integration (`git_status.lua`)

Follows the same 5-step menu pattern as all other menus:

1. **Enum**: `CHERRY_PICK = 10` added to `Menu` table
2. **Data**: `_init_menus` elseif branch with a single "Pick commit" action (`A`)
3. **Wiring**: `_init_cherry_pick_menu()` registers `on_submit` — opens `GitGraph` and calls `repo:cherry_pick(oid)` on commit selection
4. **Dispatch table**: `MENU_INITS[Menu.CHERRY_PICK] = GitStatus._init_cherry_pick_menu`
5. **Keybinding**: `file_tree:map("n", "A", self:_menu_handlers(Menu.CHERRY_PICK), map_options)`

The menu is lazily constructed on first `A` keypress and cached in `self._menus[10]`.

### Data Flow

```
A keypress
  -> _menu_handlers closure
    -> lazy _init_cherry_pick_menu() -> cached
    -> menu:mount()

A selection in menu
  -> on_submit("A", _)
    -> GitGraph(ns_id, repo):render():mount()

<Enter>/<Space> on commit in graph
  -> graph:unmount()
  -> callback(commit_node)
    -> git2.ObjectId.from_string(commit.oid)
    -> repo:cherry_pick(oid)
      -> git_cherrypick_commit (in-memory index)
      -> git_index_write_tree_to
      -> git_commit_create (new commit on HEAD)
    -> notifier feedback
    -> update_then_render()
```

### Error Handling

Follows the codebase convention:

- `repo:cherry_pick(oid)` returns a non-zero integer on failure
- `notifier.error("Cherry-pick failed", err)` is called on failure
- `notifier.info("Cherry-picked " .. short_oid)` is called on success

Common failure causes: merge conflicts (`GIT_EUNMERGED`), invalid OID, or detached HEAD with no target commit.

### Testing

Tests live in `spec/fugit2/core/cherry_pick_spec.lua`.

| Test | Coverage |
|------|----------|
| `cherry_pick` applies commit from another branch | Returns 0, new commit created on HEAD |
| In-memory: no working directory changes | `new.txt` absent from workdir; HEAD has advanced |
| New commit contains cherry-picked file | `git show HEAD:new.txt` returns expected content |
| `cherry_pick` with invalid OID | Returns non-zero error |

Run tests with:

```bash
luarocks test --local -- --config-file=nlua.busted spec/fugit2/core/cherry_pick_spec.lua
```
