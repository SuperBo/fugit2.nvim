# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
make test      # Run tests (busted via luarocks with nlua runtime)
make format    # Format Lua code with stylua (lua/ and spec/ dirs)
make deps      # Install dependencies via luarocks
```

Always run `make format` (or `stylua lua/ spec/` directly) after editing any Lua file. If `stylua` is not on PATH, install it via `brew install stylua` (macOS) or the [stylua releases page](https://github.com/JohnnyMorganz/StyLua/releases).

To run a single test file:
```bash
luarocks test --local -- --config-file=nlua.busted spec/git2_spec.lua
```

Stylua config: 120-column width, 2-space indent, LuaJIT syntax, `AutoPreferDouble` quotes, no call parentheses.

## Architecture

**fugit2.nvim** is a Neovim git GUI plugin that wraps libgit2 (C library) via LuaJIT FFI, providing a Magit-like interface with floating windows.

### Entry Points

- `plugin/fugit2.lua` — Registers Neovim commands (`:Fugit2`, `:Fugit2Graph`, `:Fugit2Diff`, `:Fugit2Blame`, etc.)
- `lua/fugit2/init.lua` — Plugin setup, repository caching, command handlers; exports `git_status`, `git_graph`, `git_diff`, `git_blame`

### Layer Structure

```
plugin/fugit2.lua
  └─ lua/fugit2/init.lua       (repo lifecycle, command dispatch)
       ├─ core/                 (git operations)
       │    ├─ libgit2.lua      (raw FFI C definitions for libgit2)
       │    ├─ git2.lua         (Lua wrappers — the main git API, ~122KB)
       │    ├─ gpgme.lua + git_gpg.lua  (GPG signing)
       │    ├─ blame.lua        (blame data structures)
       │    ├─ fzf.lua          (fuzzy-find integration)
       │    └─ pendulum.lua     (date/time formatting)
       ├─ view/                 (NUI-based UI)
       │    ├─ git_status.lua   (main status window, ~80KB — largest view)
       │    ├─ git_graph.lua    (commit graph)
       │    ├─ git_diff.lua     (diff viewer)
       │    ├─ git_blame.lua / git_blame_file.lua
       │    ├─ git_rebase.lua   (interactive rebase UI)
       │    ├─ components/      (reusable UI pieces: commit_log_view, file_tree_view, patch_view, menus, etc.)
       │    └─ ui.lua           (window factory)
       ├─ config.lua            (configuration defaults and merging)
       ├─ notifier.lua          (vim.notify wrappers)
       └─ util/dynamic_array.lua
```

### Key Design Points

- **FFI bindings**: `core/libgit2.lua` declares C types/functions; `core/git2.lua` wraps them into Lua objects. All git operations go through this layer — no shell subprocess calls.
- **Repository caching**: `init.lua` caches opened `git2.Repository` objects keyed by working directory, supporting worktrees.
- **NUI UI**: All windows/popups are built with `nui.nvim`. Views own their keymaps and handle their own async refresh logic.
- **Views are independent**: Each major feature (status, diff, blame, graph, rebase) is a self-contained view module that receives a repository object and manages its own lifecycle.

### Testing

Tests live in `spec/` and use the `busted` framework with `nlua` (Neovim Lua runtime). CI runs on Linux (Neovim stable + nightly) and macOS (stable). libgit2 must be installed on the system (`libgit2-dev` on Linux, `libgit2` via Homebrew on macOS).
