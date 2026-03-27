# Stash Management

Fugit2 provides full stash management through libgit2's native stash API — no shell subprocess calls.

## Opening the Stash Menu

From the status window (`:Fugit2`), press `z` to open the stash menu.

## Stash Menu Actions

| Key | Action | Description |
|-----|--------|-------------|
| `z` | Save | Stash current working directory changes. Prompts for an optional message. |
| `p` | Pop | Apply the top stash and remove it from the stash list. |
| `a` | Apply | Apply the top stash without removing it. |
| `d` | Drop | Delete the top stash. A confirmation prompt is shown before dropping. |
| `l` | List | Open a browsable stash list popup. |

## Argument Toggles

The stash menu includes two toggle arguments that modify the save behavior. Toggle them before pressing `z` (save).

| Key | Argument | Description |
|-----|----------|-------------|
| `-u` | Include untracked files | Stash untracked files in addition to tracked changes. |
| `-k` | Keep index | Leave staged (index) changes intact; only stash unstaged changes. |

These toggles follow the same checkbox pattern used in other fugit2 menus (commit, push, pull). Their state is preserved for the lifetime of the status window.

### Flag Combinations

| `-u` | `-k` | Behavior |
|------|------|----------|
| off | off | Stash tracked, modified files only (default). |
| on | off | Stash tracked modifications and untracked files. |
| off | on | Stash only unstaged changes; staged changes remain in the index. |
| on | on | Stash unstaged changes and untracked files; staged changes remain. |

## Stash List

Pressing `l` in the stash menu opens a floating popup listing all stashes:

```
┌─ Stashes ──────────────────────────────────────────────────────────┐
│  stash@{0}  WIP on main: fix login bug                            │
│  stash@{1}  experiment: try new layout                            │
│  stash@{2}  On feature/auth: half-done oauth flow                 │
└─────────────────────────── a:apply  p:pop  d:drop  q:quit ────────┘
```

### Stash List Keybindings

| Key | Action |
|-----|--------|
| `a` | Apply the stash at cursor (keeps the stash). |
| `p` | Pop the stash at cursor (apply + remove). |
| `d` | Drop the stash at cursor. A confirmation prompt is shown. |
| `q` / `<Esc>` | Close the stash list. |

Use `j`/`k` to navigate between stashes. The cursor line is highlighted.

### Behavior After Actions

- **Apply**: The status view refreshes to reflect the restored changes. The stash list remains open.
- **Pop**: The status view refreshes and the stash list closes (the entry is gone).
- **Drop**: The stash list re-fetches and re-renders. If no stashes remain, the list closes automatically. Stash indices shift down after a drop, so the list always shows correct indices.

## Custom Stash Messages

When saving a stash (`z`), an input prompt appears:

```
Stash message (optional):
```

- Type a message and press `<Enter>` to save with that message.
- Press `<Enter>` with an empty input to save with the default message (e.g., `WIP on branch: commit message`).
- Press `<Esc>` to cancel the save entirely.

The input prompt respects `vim.ui.input` overrides, so plugins like [dressing.nvim](https://github.com/stevearc/dressing.nvim) will style it automatically.

---

## Technical Details

This section covers the implementation architecture for contributors and maintainers.

### Files Changed

| File | Role |
|------|------|
| `lua/fugit2/core/libgit2.lua` | FFI C declarations for stash API |
| `lua/fugit2/core/git2.lua` | `Repository` Lua wrapper methods |
| `lua/fugit2/view/components/stash_list_view.lua` | Stash list popup component (new file) |
| `lua/fugit2/view/git_status.lua` | Menu integration and action methods |

### FFI Layer (`libgit2.lua`)

#### C Declarations

Added inside the `ffi.cdef` block:

```c
typedef int (*git_stash_cb)(
  size_t index, const char *message,
  const git_oid *stash_id, void *payload
);

typedef struct {
  unsigned int version;
  uint32_t flags;
  git_checkout_options checkout_options;
  void *progress_cb;
  void *progress_payload;
} git_stash_apply_options;

int git_stash_save(git_oid *out, git_repository *repo,
    const git_signature *stasher, const char *message, uint32_t flags);
int git_stash_apply(git_repository *repo, size_t index,
    const git_stash_apply_options *options);
int git_stash_pop(git_repository *repo, size_t index,
    const git_stash_apply_options *options);
int git_stash_drop(git_repository *repo, size_t index);
int git_stash_foreach(git_repository *repo, git_stash_cb callback,
    void *payload);
```

#### Constants

```lua
M.GIT_STASH = {
  DEFAULT           = 0,
  KEEP_INDEX        = 1,   -- (1 << 0)
  INCLUDE_UNTRACKED = 2,   -- (1 << 1)
  INCLUDE_IGNORED   = 4,   -- (1 << 2)
  KEEP_ALL          = 8,   -- (1 << 3)
}

M.GIT_STASH_APPLY = {
  DEFAULT         = 0,
  REINSTATE_INDEX = 1,   -- (1 << 0)
}
```

#### Init Table

```lua
M.GIT_STASH_APPLY_OPTIONS_INIT = {
  { M.GIT_STASH_APPLY_OPTIONS_VERSION, 0, M.GIT_CHECKOUT_OPTIONS_INIT[1] },
}
```

Currently unused — `stash_apply` and `stash_pop` pass `nil` for options, which makes libgit2 use safe defaults. The init table is provided for future use (e.g., `REINSTATE_INDEX` flag, custom checkout strategy).

### Repository Methods (`git2.lua`)

Five methods added to the `Repository` class, following the existing `result, err_code` return convention.

#### `stash_save(signature, message, flags)`

- Allocates a `git_oid[1]` for the output
- Passes `signature.sign` (raw `ffi.cdata*`) as the stasher identity
- `message` can be `nil` for the default libgit2 message
- `flags` is a bitwise OR of `GIT_STASH` values
- Returns `ObjectId, 0` on success

#### `stash_list()`

This is the first use of `ffi.cast("callback_type", lua_function)` in the codebase. Previous iteration patterns used either iterator objects (`git_branch_iterator`) or revwalk-style next calls.

```lua
function Repository:stash_list()
  local entries = {}
  local cb = ffi.cast("git_stash_cb", function(index, message, stash_id, _payload)
    entries[#entries + 1] = {
      index = tonumber(index),
      message = message ~= nil and ffi.string(message) or "",
      oid = ObjectId.from_git_oid(stash_id),
    }
    return 0
  end)
  local err = libgit2_C.git_stash_foreach(self.repo, cb, nil)
  cb:free()
  return entries, err ~= 0 and err or 0
end
```

**Key constraints:**

1. **`cb:free()` is mandatory** — LuaJIT FFI callbacks are allocated from a fixed pool. Failing to free leaks a slot. The callback is created and freed synchronously within a single function call, so only one slot is ever occupied.

2. **LuaJIT callback limit** — LuaJIT supports approximately 8 simultaneous live FFI callbacks. Since `stash_list` uses exactly one and frees it before returning, this is safe. However, if future code needs multiple concurrent callbacks, this limit must be considered.

3. **OID copying** — The `stash_id` pointer passed to the callback is only valid for the duration of that callback invocation. `ObjectId.from_git_oid(stash_id)` allocates a fresh `git_oid[1]` and copies the bytes via `git_oid_cpy`, making it safe to store.

4. **`ffi.string(message)`** — The message pointer is also transient. `ffi.string` copies the bytes into a Lua string immediately.

5. **No early returns** between `ffi.cast` and `cb:free()` — the code is structured to ensure the callback is always freed.

#### `stash_apply(index)` / `stash_pop(index)` / `stash_drop(index)`

Simple wrappers that pass `nil` for apply options (safe checkout defaults). Return the integer error code directly.

### Stash List View (`stash_list_view.lua`)

#### Design

Modeled on `CommitLogView` with simplifications:

| Aspect | CommitLogView | StashListView |
|--------|--------------|---------------|
| Lines per item | 2 (graph pre-line + commit) | 1 |
| Cursor-to-index | `math.floor((linenr + 1) / 2)` | `linenr` directly |
| Data source | Git walker iterator | `Repository:stash_list()` table |
| Backing store | `NuiTree` / complex graph | Plain `NuiLine[]` array |

#### Class Structure

```
StashListView (NUI Object)
  ├── popup: NuiPopup        — the floating window
  ├── _entries: StashEntry[] — data from Repository:stash_list()
  ├── _lines: NuiLine[]      — rendered lines (1:1 with entries)
  └── _action_fn: function?  — callback registered via on_action()
```

#### Rendering Cycle

Follows the standard codebase pattern:

1. Set buffer `modifiable = true`, `readonly = false`
2. `nvim_buf_set_lines` with plain text content
3. `NuiLine:highlight` for each line (applies extmarks)
4. Set buffer `modifiable = false`, `readonly = true`

#### Entry Format

Each stash is rendered as a single `NuiLine`:

```
stash@{0}  WIP on main: fix login bug
^^^^^^^^   ^^^^^^^^^^^^^^^^^^^^^^^^^^^
ObjectId   message (default highlight)
highlight
```

#### Action Delegation

The component does not perform git operations. It provides `on_action(fn)` and the parent (`git_status.lua`) registers a callback that handles apply/pop/drop with error handling and status refresh. This keeps the component a pure UI piece.

#### Lifecycle

- `mount()` — mounts popup, renders lines, binds keymaps
- `update(entries)` — replaces data, rebuilds lines, resizes popup, re-renders
- `close()` — unmounts popup

Popup height auto-adjusts to `min(#entries, 15)` on both `init` and `update`.

### Status View Integration (`git_status.lua`)

#### Menu Wiring

Follows the exact same 5-step pattern as all other menus:

1. **Enum**: `STASH = 9` added to `Menu` table
2. **Data**: `_init_menus` elseif branch with `menu_items` (5 actions + 2 section headers) and `arg_items` (2 checkboxes)
3. **Wiring**: `_init_stash_menu()` calls `_init_menus(Menu.STASH)` then registers `on_submit` dispatcher
4. **Dispatch table**: `MENU_INITS[Menu.STASH] = GitStatus._init_stash_menu`
5. **Keybinding**: `file_tree:map("n", "z", self:_menu_handlers(Menu.STASH), map_options)`

The menu is lazily constructed on first `z` keypress and cached in `self._menus[9]`.

#### Action Methods

| Method | Description |
|--------|-------------|
| `stash_save(args)` | Builds flags from arg strings, prompts via `vim.ui.input`, calls `repo:stash_save` |
| `stash_pop()` | Calls `repo:stash_pop(0)` on top stash |
| `stash_apply()` | Calls `repo:stash_apply(0)` on top stash |
| `stash_drop()` | Shows `UI.Confirm` then calls `repo:stash_drop(0)` |
| `stash_list_show()` | Fetches entries, creates `StashListView`, wires `on_action` callback |

#### Flag Mapping in `stash_save`

The menu arg system produces string arrays keyed by model name. The `stash_flags` model yields:

```lua
args["stash_flags"] = { "--include-untracked", "--keep-index" }
```

These are mapped to libgit2 flags via `bit.bor`:

```lua
"--include-untracked" -> GIT_STASH.INCLUDE_UNTRACKED (2)
"--keep-index"        -> GIT_STASH.KEEP_INDEX (1)
```

#### Stash List Action Handler

The `on_action` callback in `stash_list_show` handles three cases:

- **apply** — applies, refreshes status view, list stays open
- **pop** — pops, refreshes, closes list (entry is gone)
- **drop** — shows `UI.Confirm`, drops, re-fetches list via `repo:stash_list()`, updates or closes list if empty

Drop re-fetches the entire list because libgit2 renumbers all stash indices above the dropped one. There is no incremental update possible.

#### Signature Handling

`stash_save` uses `self._git.signature` which is cached during `GitStatus:init()` via `repo:signature_default()`. This avoids repeated FFI calls to read the git config for user name/email.

### Data Flow

```
z keypress
  -> _menu_handlers closure
    -> lazy _init_stash_menu() -> cached
    -> menu:mount()

z/p/a/d/l selection in menu
  -> on_submit(item_id, args)
    -> stash_save/pop/apply/drop/list_show

stash_save:
  vim.ui.input -> vim.schedule ->
    repo:stash_save(signature, message, flags)
      -> libgit2_C.git_stash_save(oid, repo, sig, msg, flags)
    -> update_then_render()

stash_list_show:
  repo:stash_list()
    -> ffi.cast("git_stash_cb", fn) + git_stash_foreach + cb:free()
  -> StashListView(ns_id, entries)
  -> view:on_action(callback)
  -> view:mount()

stash list action:
  a/p/d keypress -> get_entry() -> _action_fn("apply"/"pop"/"drop", entry)
    -> repo:stash_apply/pop/drop(entry.index)
    -> notifier feedback
    -> update_then_render()
    -> view:update() or view:close()
```

### Error Handling

All methods follow the codebase convention:

- FFI calls return integer error codes (0 = success)
- On failure, `notifier.error(message, err_code)` is called
- No exceptions or pcall wrappers — errors are communicated via return values
- `git2.error_last()` is not used (consistent with the rest of `git_status.lua`)

### Design Decisions & Risks

1. **LuaJIT callback limit**: LuaJIT supports max ~8 live FFI callbacks. `stash_list` creates and frees one synchronously within a single call, so this is safe. Never store the callback beyond the `git_stash_foreach` call — doing so would leak a slot from the fixed pool and risk hitting the limit.

2. **ObjectId copying in callback**: The `stash_id` pointer passed to the foreach callback is only valid during that invocation. `ObjectId.from_git_oid(stash_id)` handles this by allocating a fresh `git_oid[1]` and copying the bytes via `git_oid_cpy`, making the resulting `ObjectId` safe to store in the entries table.

3. **Stash index stability**: After a `stash_drop`, all indices above the dropped one shift down. The stash list must be re-fetched after any drop operation before allowing further actions. The implementation handles this by calling `repo:stash_list()` after every successful drop and updating or closing the view accordingly.

4. **`vim.ui.input` for message**: Using `vim.ui.input` (rather than a NUI popup) for the stash message is simpler and works with user-configured UI overrides (dressing.nvim, etc.). The existing branch input uses NUI prompt buffers, but those are more complex than needed for a single optional string. Pressing `<Esc>` cancels the save entirely; empty input uses libgit2's default message.

### Testing

Tests live in two spec files:

**`spec/fugit2/core/stash_spec.lua`** — Repository method tests using a temporary git repo:

| Test | Coverage |
|------|----------|
| `stash_list` with 0 stashes | Empty list returns `{}` with no error |
| `stash_save` with default message | Tracked changes are stashed, oid returned |
| `stash_save` with custom message | Message preserved in stash list |
| `stash_save` with `INCLUDE_UNTRACKED` | Untracked files are removed from working dir |
| `stash_save` with `KEEP_INDEX` | Staged changes remain after save |
| `stash_save` with nothing to stash | Returns non-zero error |
| `stash_list` with multiple stashes | Correct order (newest first), valid indices and oids |
| `stash_list` oid validity | OID bytes survive callback (copied, not borrowed) |
| `stash_apply` | Changes restored, stash remains in list |
| `stash_apply` invalid index | Returns non-zero error |
| `stash_drop` | List shrinks by one |
| `stash_drop` index renumbering | After dropping `@{0}`, previous `@{1}` becomes `@{0}` |
| `stash_drop` invalid index | Returns non-zero error |
| `stash_pop` | Changes restored and stash removed from list |
| `stash_pop` invalid index | Returns non-zero error |

**`spec/fugit2/view/stash_list_view_spec.lua`** — View component tests with mock entries (no repo needed):

| Test | Coverage |
|------|----------|
| `_build_lines` empty | No lines for empty entries |
| `_build_lines` single entry | Correct `stash@{N}` prefix and message |
| `_build_lines` multiple entries | All entries rendered with correct indices |
| `_build_lines` empty message | Handles gracefully |
| `get_entry` by line number | 1-based line maps directly to entry |
| `get_entry` out of range | Returns `nil` |
| `get_entry` no winid | Returns `nil` when popup not mounted |
| `update` replaces data | Lines rebuilt with new entries |
| `update` to empty | Lines cleared |
| `on_action` callback | Action string and entry passed correctly |

Run tests with:

```bash
luarocks test --local -- --config-file=nlua.busted spec/fugit2/core/stash_spec.lua
luarocks test --local -- --config-file=nlua.busted spec/fugit2/view/stash_list_view_spec.lua
```
