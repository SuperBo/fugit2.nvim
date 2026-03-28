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
4. The commit's changes are applied to the working directory and staged in the index.
5. Use the commit menu (`c`) to create the cherry-pick commit.

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
int git_cherrypick(git_repository *repo, git_commit *commit,
    const git_cherrypick_options *cherrypick_options);
```

#### Constants

```lua
M.GIT_CHERRYPICK_OPTIONS_VERSION = 1
M.GIT_CHERRYPICK_OPTIONS_INIT = {
  {
    M.GIT_CHERRYPICK_OPTIONS_VERSION,
    0,  -- mainline (0 = not a merge commit)
    M.GIT_MERGE_OPTIONS_INIT[1],
    M.GIT_CHECKOUT_OPTIONS_INIT[1],
  },
}
```

### Repository Method (`git2.lua`)

```lua
function Repository:cherry_pick(oid)
```

- Looks up the commit via `self:commit_lookup(oid)` — returns early with the error code if the OID is invalid
- Allocates `git_cherrypick_options[1]` initialized with `GIT_CHERRYPICK_OPTIONS_INIT`
- Calls `git_cherrypick(repo, commit.commit, opts)`
- Returns the integer error code (0 = success)

`git_cherrypick` applies the diff introduced by the commit onto the current HEAD, modifying the working directory and staging the changes in the index. It does **not** create a commit — the user must commit separately.

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
      -> libgit2_C.git_cherrypick(repo, commit.commit, opts)
    -> notifier feedback
    -> update_then_render()
```

### Error Handling

Follows the codebase convention:

- `repo:cherry_pick(oid)` returns a non-zero integer on failure
- `notifier.error("Cherry-pick failed", err)` is called on failure
- `notifier.info("Cherry-picked " .. short_oid)` is called on success

Common failure causes: merge conflicts (the cherry-pick cannot be applied cleanly), invalid OID, or detached HEAD with no target commit.

### Testing

Tests live in `spec/fugit2/core/cherry_pick_spec.lua`.

| Test | Coverage |
|------|----------|
| `cherry_pick` applies commit from another branch | Returns 0, commit is applied |
| Staged changes after cherry-pick | Working directory contains the cherry-picked file |
| `cherry_pick` with invalid OID | Returns non-zero error |

Run tests with:

```bash
luarocks test --local -- --config-file=nlua.busted spec/fugit2/core/cherry_pick_spec.lua
```
