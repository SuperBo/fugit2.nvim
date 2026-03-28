# Rebase Technical Details

## Overview

fugit2.nvim implements interactive rebase using libgit2's C API via LuaJIT FFI.
Rebase can operate in two modes: **in-memory** and **on-disk**.

## In-Memory vs On-Disk Rebase

### In-Memory Rebase

When a new rebase is initiated from the UI (via ref or revspec config), fugit2
uses libgit2's in-memory mode (`git_rebase_options.inmemory = 1`).

In-memory rebase applies commits entirely in memory without writing intermediate
state to the working directory or `.git/rebase-merge/`. This means:

- Commits are replayed using an in-memory index (`git_rebase_inmemory_index`).
- No rebase state files are written to `.git/`.
- The working directory is **not modified** during the rebase operation itself.
- After all operations complete, fugit2 must explicitly:
  1. Update the HEAD ref to point to the final rebased commit
     (`Repository:update_head_for_commit`).
  2. Checkout HEAD to synchronize the working directory with the new commit tree
     (`Repository:checkout_head(GIT_CHECKOUT.FORCE)`).

**Entry points** (both set `inmemory = true`):
- `_init_rebase_ref()` — rebase from `GitReference` objects
- `_init_rebase_revspec()` — rebase from revspec strings (e.g., `"main"`,
  `"HEAD~3"`)

### On-Disk Rebase

When reopening an existing rebase (`Repository:rebase_open`), the rebase
operates on disk. libgit2 writes state to `.git/rebase-merge/` and modifies the
working directory as each operation is applied. No additional checkout step is
needed after finishing.

**Entry point**: `RebaseView:init` with no `ref_config` or `revspec_config`
(calls `repo:rebase_open()`).

## Rebase Lifecycle

```
rebase_init (inmemory=true)
    |
    v
rebase_start()          -- reorder/remap operations, remove edit keymaps
    |
    v
rebase_continue()       -- loop: next -> commit/amend, handle DROP/SQUASH/FIXUP
    |                      breaks on ITEROVER, EUNMERGED, or error
    |
    +-- ITEROVER -------> rebase_finish()
    |                       1. git_rebase_finish()
    |                       2. update HEAD ref (inmemory only)
    |                       3. checkout HEAD to disk (inmemory only)
    |
    +-- EUNMERGED ------> rebase_has_conflicts()
    |                       show conflict UI -> resolve -> rebase_continue()
    |
    +-- error ----------> rebase_abort()
```

## Key Operations

### Commit (`Rebase:commit`)

Calls `git_rebase_commit` to create a new commit from the current rebase
operation's index state. Works for both in-memory and on-disk modes — libgit2
handles the distinction internally.

### Amend (`Rebase:amend`)

Used for SQUASH and FIXUP operations. In-memory mode uses a custom
implementation (`_rebase_amend_inmemory`) that:

1. Retrieves the in-memory index and last commit from the rebase struct.
2. Writes the index tree to the repository.
3. Calls `git_commit_amend` to create an amended commit.
4. Updates the rebase's `last_commit` pointer.

On-disk amend is **not implemented** (returns error).

### Skip (`Rebase:skip`)

Used for DROP operations. Directly manipulates the rebase struct's internal
`current` counter to advance past the operation without applying it. This
bypasses `git_rebase_next` since libgit2 does not provide a native skip API.

### Conflict Resolution

When `git_rebase_next` or `git_rebase_commit` returns `GIT_EUNMERGED`:

- **In-memory**: conflicts exist in the rebase's in-memory index
  (`rebase:inmemory_index()`). The diff view receives this index along with
  the current commit as HEAD context.
- **On-disk**: conflicts exist in the repository's working index
  (`repo:index()`). Standard diff resolution applies.

After conflicts are resolved, `rebase_continue()` detects that
`rebase_error == GIT_EUNMERGED`, re-checks the index, and proceeds if
conflicts are cleared.

## Supported Rebase Actions

| Action  | Enum | Behavior                                            |
|---------|------|-----------------------------------------------------|
| PICK    | 0    | Apply commit as-is                                  |
| REWORD  | 1    | Apply commit with modified message                  |
| EDIT    | 2    | Apply commit, pause for editing                     |
| SQUASH  | 3    | Meld into previous commit, combine messages         |
| FIXUP   | 4    | Meld into previous commit, discard this message     |
| EXEC    | 5    | Run a command (not used in UI)                      |
| DROP    | 6    | Skip this commit entirely                           |
| BREAK   | 7    | Pause rebase at this point                          |
| BASE    | 8    | Marker for the base (onto) commit in the UI         |

DROP is mapped to `GIT_REBASE_OPERATION.EXEC` with a nil exec string in
libgit2, then handled via `Rebase:skip()` during execution.

## Code Locations

| Component               | File                                    |
|--------------------------|-----------------------------------------|
| FFI C declarations       | `lua/fugit2/core/libgit2.lua`           |
| Lua wrapper (Rebase API) | `lua/fugit2/core/git2.lua`              |
| Rebase helper (Fugit2)   | `lua/fugit2/core/git_rebase_helper.lua` |
| Rebase UI view           | `lua/fugit2/view/git_rebase.lua`        |
| Tests                    | `spec/fugit2/core/rebase_spec.lua`      |
