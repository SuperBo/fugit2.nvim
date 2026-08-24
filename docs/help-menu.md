# Help Menu

Fugit2 provides a discoverable keymap help popup in every view. Press `?` to see all
keybindings available in the current view, with the descriptions from the keymap
registry. The listed keys reflect any remaps you configured through `opts.keymaps`.

## Opening the Help Popup

| View | Where | Key |
|------|-------|-----|
| Status window — file tree | `:Fugit2` | `?` |
| Status window — commit log | `:Fugit2` (right panel) | `?` |
| Status window — patch views | `:Fugit2` (patch panel) | `?` |
| Interactive rebase | `:Fugit2Rebase` | `?` |
| Commit graph — log pane | `:Fugit2Graph` | `?` |
| Commit graph — branch pane | `:Fugit2Graph` | `?` |
| Diff view | `:Fugit2Diff` | `?` |
| Stash list | `:Fugit2` → `z` → `l` | `?` |

## Example

```
┌──── File Tree ──────┐
│ ?         Show keymap help  │
│ D / x     Discard changes   │
│ a         Stage/unstage all │
│ s         Stage file        │
│ u         Unstage file      │
│ =         Toggle patch view │
│ ...                          │
└──────── q/esc/? close ──────┘
```

Keys are highlighted with the `Fugit2HelpKey` highlight group; descriptions use the
default highlight.

## Closing

- `q` / `<Esc>` / `?` closes the help popup and returns focus to the calling view.

## Remapping the help key

The `?` binding is registered in the keymap registry under the `help` action of each
view group, so it can be remapped (or disabled) like any other key:

```lua
opts = {
  keymaps = {
    file_tree = { help = "H" },
    rebase = { help = false },   -- disable help in rebase view
  },
}
```

---

## Technical Details

### Files Changed

| File | Role |
|------|------|
| `lua/fugit2/view/components/help_view.lua` | New `HelpView` popup component |
| `lua/fugit2/view/keymaps.lua` | `help` action per group + `help_entries()` resolver |
| `lua/fugit2/view/git_status.lua` | `?` bound in file tree, commit log, patch views via `_show_help()` |
| `lua/fugit2/view/git_rebase.lua` | `?` bound in the rebase commit view |
| `lua/fugit2/view/git_graph.lua` | `?` bound in graph log and branch panes |
| `lua/fugit2/view/git_diff.lua` | `?` bound in the diff source tree |
| `lua/fugit2/view/components/stash_list_view.lua` | `?` bound in the stash list |
| `lua/fugit2/view/colors.lua` | `Fugit2HelpKey` highlight group |
| `spec/fugit2/view/help_view_spec.lua` | Component specs |
| `spec/fugit2/view/keymaps_spec.lua` | `help_entries` specs |

### Component: `HelpView`

Modeled on `stash_list_view.lua` — a pure-read NUI popup that renders `NuiLine[]`
from pre-resolved entries:

```lua
HelpView:init(ns_id, title, entries)   -- entries: { keys, desc, mode? }[]
HelpView:mount()                        -- render + bind q/esc/? close
HelpView:close()                        -- unmount (safe when not mounted)
```

- Popup size: `width = 60`, `height = min(#entries + 1, 20)`.
- Keys are right-padded to align descriptions; `""` keys render as `<disabled>`.
- The popup is `enter = true` and focusable; closing returns focus to the caller's
  window.

### Registry Integration

The `?` binding lives in the registry as the `help` action in every help-capable group:

```lua
file_tree = { help = { keys = "?", desc = "Show keymap help" }, ... }
```

Views add a `help` handler that calls `keymaps.help_entries(group, user)` and mounts
the popup. Because `help_entries` applies `opts.keymaps` overrides, the popup always
reflects the user's actual bindings.

### Data Flow

```
? keypress
  -> view:help handler
    -> keymaps.help_entries(group, config.get_keymaps(group))
         -> defaults[group] iterated, user overrides applied
         -> disabled (false) omitted, multi-keys joined with " / "
         -> sorted by desc
    -> HelpView(ns_id, title, entries):mount()
         -> NuiPopup + _build_lines()
         -> render() via nvim_buf_set_lines + NuiLine:highlight

q / <esc> / ? in popup
  -> HelpView:close()
    -> popup:unmount()
```

### Testing

Tests live in two spec files:

**`spec/fugit2/view/help_view_spec.lua`** — component line building:

| Test | Coverage |
|------|----------|
| `_build_lines` empty | No lines for empty entries |
| `_build_lines` single | Key + description rendered |
| `_build_lines` multiple | All entries rendered |
| Key padding | Descriptions aligned to the longest key |
| Disabled placeholder | `""` keys render as `<disabled>` |
| `close` unmounted | Safe when popup not mounted |

**`spec/fugit2/view/keymaps_spec.lua`** — `help_entries` resolver:

| Test | Coverage |
|------|----------|
| Entry per action | All defs produce a row with keys + desc |
| Multi-key join | `{ "D", "x" }` renders as `"D / x"` |
| User overrides | Remapped keys reflected in output |
| Disabled omitted | `false` actions excluded |
| No-op included | `""` actions appear with empty key |
| Unknown group | Returns empty list |
| Sorted by description | Stable, readable ordering |

Run tests with:

```bash
luarocks test --local -- --config-file=nlua.busted spec/fugit2/view/help_view_spec.lua
luarocks test --local -- --config-file=nlua.busted spec/fugit2/view/keymaps_spec.lua
```
