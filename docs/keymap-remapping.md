# Keymap Remapping

Fugit2 exposes **every** keybinding across **all** views as configurable through the
`opts.keymaps` setup option. A central keymap registry
(`lua/fugit2/view/keymaps.lua`) is the single source of truth for defaults, user
overrides, and the upcoming help menu.

## Configuring Keymaps

Pass `keymaps` in your `setup`/`opts` table, grouped by view. Each action accepts:

| Value | Effect |
|-------|--------|
| `"key"` | Remap to a single key. |
| `{ "k1", "k2" }` | Bind multiple keys. |
| `false` | Disable the binding entirely (not mapped). |
| `""` | Bind as a no-op (consumes the key, does nothing). |

```lua
opts = {
  keymaps = {
    file_tree = {
      stage_file = "S",          -- stage now on S (default s)
      unstage_file = false,      -- remove the default u binding
      discard = { "X", "D" },    -- discard on X or D
      menu_commit = "C",         -- menu actions use menu_<action> ids
    },
    commit_log = {
      copy_oid = "yY",
    },
    rebase = {
      drop = { "x", "d" },
      move_down = "<C-j>",
    },
  },
}
```

Keys are resolved per-view at mount time, so a change to `opts.keymaps` takes effect
the next time a view is opened.

## View Groups

| Group | Applies to | Notable actions |
|-------|------------|-----------------|
| `file_tree` | Status file tree | `stage_file`, `unstage_file`, `discard`, `menu_*`, `exit` |
| `commit_log` | Status commit log | `copy_oid`, `quick_jump_down`, `focus_file_tree` |
| `patch_unstaged` | Unstaged patch panel | `stage_hunk`, `discard_hunk`, `jump_file` |
| `patch_staged` | Staged patch panel | `unstage_hunk`, `jump_file` |
| `rebase` | Interactive rebase view | `pick`, `squash`, `fixup`, `reword`, `drop`, `move_up`/`down` |
| `graph_log` | Commit graph log pane | `copy_oid`, `focus_branch` |
| `graph_branch` | Commit graph branch pane | `focus_log` |
| `graph_select` | Graph commit/branch selection | `select_commit`, `select_branch` |
| `diff` | Diff view source tree | `stage_file`, `unstage_file`, `focus_pane` |
| `stash_list` | Stash list popup | `apply`, `pop`, `drop` |
| `pick` | Branch/ref picker input | `next_item`, `prev_item` |
| `input` | Commit/branch/reword input prompts | `enter`, `exit` |
| `confirm` | Yes/No confirmation popups | `yes`, `move_yes`, `move_no`, `exit` |
| `blame` | Blame split view | `next_hunk`, `prev_hunk` |
| `blame_file` | Inline blame (virtual text) | `show_detail`, `exit` |
| `blame_popup` | Blame hunk detail popup | `exit` |
| `patch` | Hunk navigation in patch panels | `next_hunk`, `prev_hunk` |

## Default Keybindings

### file_tree

| Action | Keys | Description |
|--------|------|-------------|
| `exit` | `q`, `<esc>` | Close window |
| `exit_insert` | `<c-c>` | Close window (insert mode) |
| `refresh` | `g` | Refresh status |
| `menu_rebase` | `r` | Open rebase menu |
| `collapse` | `h` | Collapse folder |
| `collapse_all` | `H` | Collapse all folders |
| `expand` | `l` | Expand folder / open patch view |
| `expand_all` | `L` | Expand all folders |
| `focus_commit_log` | `J`, `<tab>` | Move to commit log |
| `focus_commit_log_disable` | `K` | No-op: disable mirror pane move |
| `toggle_patch` | `=` | Toggle patch view |
| `open_file` | `<cr>` | Open file |
| `stage_all` | `a` | Stage/unstage all |
| `stage_toggle` | `-`, `<space>` | Stage/unstage file |
| `stage_file` | `s` | Stage file |
| `unstage_file` | `u` | Unstage file |
| `discard` | `D`, `x` | Discard changes |
| `write_index` | `w` | Write index |
| `stage_toggle_visual` | `-`, `<space>` | Stage/unstage selection (visual) |
| `stage_visual` | `s` | Stage selection (visual) |
| `unstage_visual` | `u` | Unstage selection (visual) |
| `discard_visual` | `x`, `d` | Discard selection (visual) |
| `menu_commit` | `c` | Open commit menu |
| `menu_diff` | `d` | Open diff menu |
| `menu_branch` | `b` | Open branch menu |
| `menu_push` | `P` | Open push menu |
| `menu_fetch` | `f` | Open fetch menu |
| `menu_pull` | `p` | Open pull menu |
| `menu_forge` | `N` | Open forge menu |
| `menu_stash` | `z` | Open stash menu |
| `menu_cherry_pick` | `A` | Open cherry-pick menu |

### commit_log

| Action | Keys | Description |
|--------|------|-------------|
| `exit` | `q`, `<esc>` | Close window |
| `focus_file_tree` | `K`, `<tab>` | Move to file tree |
| `focus_file_tree_disable` | `J` | No-op: disable mirror pane move |
| `quick_jump_down` | `j` | Jump down (2 lines) |
| `quick_jump_up` | `k` | Jump up (2 lines) |
| `copy_oid` | `yy` | Copy commit id |
| `copy_oid_clipboard` | `yc` | Copy commit id to clipboard |

### patch_unstaged

| Action | Keys | Description |
|--------|------|-------------|
| `exit` | `q`, `<esc>` | Close window |
| `menu_commit` | `c` | Open commit menu |
| `menu_branch` | `b` | Open branch menu |
| `focus_file_tree` | `h` | Move to file tree |
| `focus_staged` | `l` | Move to staged patch |
| `toggle_off` | `=` | Turn off patch view |
| `stage_hunk` | `-`, `s` | Stage hunk |
| `discard_hunk` | `d`, `x` | Discard hunk |
| `stage_visual` | `-`, `s` | Stage selection (visual) |
| `discard_visual` | `d`, `x` | Discard selection (visual) |
| `jump_file` | `<cr>` | Jump to file |

### patch_staged

| Action | Keys | Description |
|--------|------|-------------|
| `exit` | `q`, `<esc>` | Close window |
| `menu_commit` | `c` | Open commit menu |
| `menu_branch` | `b` | Open branch menu |
| `focus_file_tree` | `h` | Move to file tree |
| `toggle_off` | `=` | Turn off patch view |
| `unstage_hunk` | `-`, `u` | Unstage hunk |
| `unstage_visual` | `-`, `u` | Unstage selection (visual) |
| `jump_file` | `<cr>` | Jump to file |

### rebase

| Action | Keys | Description |
|--------|------|-------------|
| `exit` | `<esc>`, `q` | Abort / close |
| `start` | `<cr>` | Start rebase |
| `continue` | `<cr>` | Continue rebase |
| `drop` | `x`, `d` | Drop commit |
| `break_commit` | `b` | Break |
| `edit` | `e` | Edit commit |
| `squash` | `s` | Squash commit |
| `fixup` | `f` | Fixup commit |
| `reword` | `r`, `w` | Reword commit |
| `pick` | `p` | Pick commit |
| `squash_visual` | `s` | Squash commits (visual) |
| `fixup_visual` | `f` | Fixup commits (visual) |
| `move_down` | `gj`, `<C-j>` | Move commit down |
| `move_up` | `gk`, `<C-k>` | Move commit up |
| `quick_jump_down` | `j` | Jump down (2 lines) |
| `quick_jump_up` | `k` | Jump up (2 lines) |
| `quick_jump_down_visual` | `j` | Jump down (visual) |
| `quick_jump_up_visual` | `k` | Jump up (visual) |

### graph_log / graph_branch

| Group | Action | Keys | Description |
|-------|--------|------|-------------|
| `graph_log` | `exit` | `q`, `<esc>` | Close window |
| `graph_log` | `refresh` | `r` | Refresh |
| `graph_log` | `focus_branch` | `h` | Move to branch view |
| `graph_log` | `quick_jump_down` | `j` | Jump down (2 lines) |
| `graph_log` | `quick_jump_up` | `k` | Jump up (2 lines) |
| `graph_log` | `copy_oid` | `yy` | Copy commit id |
| `graph_log` | `copy_oid_clipboard` | `yc` | Copy commit id to clipboard |
| `graph_branch` | `exit` | `q`, `<esc>` | Close window |
| `graph_branch` | `refresh` | `r` | Refresh |
| `graph_branch` | `focus_log` | `l`, `<cr>`, `<space>` | Move to commit log |
| `graph_select` | `select_commit` | `<cr>`, `<space>` | Select commit |
| `graph_select` | `select_branch` | `<cr>`, `<space>` | Select branch |

### diff

| Action | Keys | Description |
|--------|------|-------------|
| `exit` | `q`, `<esc>` | Close window |
| `focus_pane` | `l`, `<cr>` | Focus diff pane |
| `stage_file` | `s` | Stage file |
| `unstage_file` | `u` | Unstage file |
| `stage_toggle` | `-`, `<space>` | Stage/unstage file |
| `refresh` | `r` | Refresh |

### stash_list

| Action | Keys | Description |
|--------|------|-------------|
| `exit` | `q`, `<esc>` | Close window |
| `apply` | `a` | Apply stash |
| `pop` | `p` | Pop stash |
| `drop` | `d` | Drop stash |

### pick / input / confirm

| Group | Action | Keys | Description |
|-------|--------|------|-------------|
| `pick` | `exit` | `<esc>`, `<C-c>` | Close window (insert mode) |
| `pick` | `next_item` | `<C-n>` | Move to next item |
| `pick` | `prev_item` | `<C-p>` | Move to previous item |
| `input` | `exit` | `q`, `<esc>` | Cancel input |
| `input` | `exit_insert` | `<C-c>` | Cancel input (insert mode) |
| `input` | `enter` | `<cr>` | Confirm input |
| `input` | `enter_insert` | `<C-cr>` | Confirm input (insert mode) |
| `confirm` | `exit` | `q`, `n`, `<esc>` | No / close |
| `confirm` | `move_no` | `l` | Move to No |
| `confirm` | `move_yes` | `h` | Move to Yes |
| `confirm` | `toggle` | `<tab>` | Toggle Yes/No |
| `confirm` | `yes` | `y` | Confirm Yes |
| `confirm` | `yes_enter` | `<cr>` | Confirm Yes |

### blame / blame_file / blame_popup / patch

| Group | Action | Keys | Description |
|-------|--------|------|-------------|
| `blame` | `exit` | `q`, `<esc>` | Close window |
| `blame` | `next_hunk` | `J`, `]c` | Next hunk |
| `blame` | `prev_hunk` | `K`, `[c` | Previous hunk |
| `blame_file` | `exit` | `q`, `<esc>` | Close window |
| `blame_file` | `show_detail` | `c` | Toggle blame hunk detail |
| `blame_popup` | `exit` | `q`, `<esc>` | Close blame detail |
| `patch` | `next_hunk` | `J` | Next hunk |
| `patch` | `prev_hunk` | `K` | Previous hunk |

## Backward Compatibility

The deprecated `file_tree_maps.menu` option still works. In `config.merge`, each legacy
action is translated into the matching `keymaps.file_tree.menu_<action>` entry, so
existing configs keep working unchanged:

```lua
-- Legacy
opts = { file_tree_maps = { menu = { commit = "c", stash = "z" } } }

-- Equivalent new form
opts = {
  keymaps = {
    file_tree = {
      menu_commit = "c",
      menu_stash = "z",
    },
  },
}
```

New `keymaps` entries always take precedence over a translated legacy value. The legacy
`file_tree_maps.direct` handling is preserved for backward compatibility.

---

## Technical Details

### Files Changed

| File | Role |
|------|------|
| `lua/fugit2/view/keymaps.lua` | New central keymap registry (defaults + `bind`/`bind_buf`/`resolve_keys`) |
| `lua/fugit2/config.lua` | `keymaps` config field, `get_keymaps()`, legacy `file_tree_maps` translation |
| `lua/fugit2/view/git_status.lua` | File tree, commit log, patch views, inputs bound via registry |
| `lua/fugit2/view/git_rebase.lua` | Rebase view keymaps via registry |
| `lua/fugit2/view/git_graph.lua` | Graph log/branch/select keymaps via registry |
| `lua/fugit2/view/git_diff.lua` | Diff view keymaps via registry |
| `lua/fugit2/view/git_pick.lua` | Picker input keymaps via registry |
| `lua/fugit2/view/git_blame.lua` | Blame split view via `bind_buf` |
| `lua/fugit2/view/git_blame_file.lua` | Inline blame + detail popup via registry |
| `lua/fugit2/view/components/stash_list_view.lua` | Stash list actions via registry |
| `lua/fugit2/view/components/patch_view.lua` | Hunk navigation via registry |
| `lua/fugit2/view/components/menus.lua` | Confirm popup keys via registry |

### Registry API

`keymaps.lua` exports:

| Function | Purpose |
|----------|---------|
| `get(group, action)` | Returns the `Fugit2KeymapDef` for an action. |
| `resolve_keys(group, action, user)` | Effective keys after applying user overrides. |
| `bind(view, group, handlers, user, opts)` | Binds every action in a group with a handler to a NUI view. |
| `bind_buf(bufnr, group, handlers, user, opts)` | Same, but maps onto a raw buffer via `nui.utils.keymap`. |
| `defs(group)` | All defs for a group (used by the help menu). |

`bind` iterates `M.defaults[group]`. For each action the effective keys are
`user[action]` when present, otherwise the default. `false` disables the mapping;
`""` binds it as a no-op. Actions without a handler are skipped, so views can bind only
the subset they implement.

### Handler Resolution

Handlers are stored as functions in each view's handler table keyed by action id, not
in the registry. This keeps the registry serializable (for the help menu) and avoids
capturing stale `self` references:

```lua
local file_tree_handlers = {
  stage_file = utils.wrap(GitStatus._index_add_reset_discard, self, TreeBase.IndexAction.ADD),
  menu_commit = self:_menu_handlers(Menu.COMMIT),
  -- ...
}
keymaps.bind(file_tree, "file_tree", file_tree_handlers, self.opts.keymaps.file_tree, map_options)
```

### Data Flow

```
opts.keymaps.<group>.<action> = key
  -> config.merge()        (legacy file_tree_maps translated)
  -> view:setup_handlers()
       -> keymaps.bind(view, group, handlers, config.get_keymaps(group))
            -> for action, def in defaults[group]:
                 keys = user[action] or def.keys
                 if keys ~= false and handlers[action] then
                   view:map(def.mode or "n", keys, handlers[action], opts)
```

### Testing

Tests live in two spec files:

**`spec/fugit2/view/keymaps_spec.lua`** — registry unit tests with a mock view:

| Test | Coverage |
|------|----------|
| All view groups defined | Registry has every expected group |
| Every def has keys + desc | Completeness check |
| `get` known/unknown action/group | Lookup behavior |
| `resolve_keys` defaults/overrides/disable/no-op | Effective key resolution |
| `bind` defaults/overrides | Mapping uses effective keys |
| `bind` disabled/false | Action skipped when disabled |
| `bind` no-op handler | Empty-string handler maps as no-op |
| `bind` missing handler | Action skipped |
| `bind` unknown group | No-op |
| `bind` visual/insert modes | `mode = "v"` / `mode = "i"` honored |
| `bind_buf` delegation | Delegates to `nui.utils.keymap.set` |
| `defs` | Group defs returned |

**`spec/fugit2/config_spec.lua`** — config merge + backward-compat translation:

| Test | Coverage |
|------|----------|
| Partial args merged into defaults | `width` override keeps `height` default |
| Nested tables deep-merged | `file_tree_maps.menu.commit` override |
| Legacy `file_tree_maps.menu` translated | `menu_commit`, `menu_stash` populated |
| Defaults not translated | Defaults live in the registry, not config |
| New `keymaps` take precedence | Overrides legacy translation |
| User keymap groups intact | `file_tree`, `rebase` groups preserved |
| `keymaps.file_tree` always populated | Present after merge |

Run tests with:

```bash
luarocks test --local -- --config-file=nlua.busted spec/fugit2/view/keymaps_spec.lua
luarocks test --local -- --config-file=nlua.busted spec/fugit2/config_spec.lua
```
