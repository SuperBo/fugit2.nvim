--- Central keymap registry for all Fugit2 views.
---
--- This module is the single source of truth for default keybindings. Views bind
--- their keymaps by calling `bind` with a handlers table; user overrides from
--- `opts.keymaps` are resolved here. The same registry feeds the help menu.

---@class Fugit2KeymapDef
---@field keys string|string[] Default key binding(s). An empty string "" disables the
---  mapping (bound as a no-op). `false` disables entirely (not bound).
---@field desc string Human-readable description for the help menu.
---@field mode string Mapping mode, defaults to "n".

---@alias Fugit2KeymapHandlers table<string, function|string> action -> handler.
---  A handler of "" maps the keys to a no-op (clears the mapping).

local M = {}

---@type table<string, table<string, Fugit2KeymapDef>>
M.defaults = {
  file_tree = {
    exit = { keys = { "q", "<esc>" }, desc = "Close window" },
    exit_insert = { keys = "<c-c>", mode = "i", desc = "Close window" },
    refresh = { keys = "g", desc = "Refresh status" },
    menu_rebase = { keys = "r", desc = "Open rebase menu" },
    collapse = { keys = "h", desc = "Collapse folder" },
    collapse_all = { keys = "H", desc = "Collapse all folders" },
    expand = { keys = "l", desc = "Expand folder / open patch view" },
    expand_all = { keys = "L", desc = "Expand all folders" },
    focus_commit_log = { keys = { "J", "<tab>" }, desc = "Move to commit log" },
    focus_commit_log_disable = { keys = "K", desc = "No-op: disable mirror pane move" },
    toggle_patch = { keys = "=", desc = "Toggle patch view" },
    open_file = { keys = "<cr>", desc = "Open file" },
    stage_all = { keys = "a", desc = "Stage/unstage all" },
    stage_toggle = { keys = { "-", "<space>" }, desc = "Stage/unstage file" },
    stage_file = { keys = "s", desc = "Stage file" },
    unstage_file = { keys = "u", desc = "Unstage file" },
    discard = { keys = { "D", "x" }, desc = "Discard changes" },
    write_index = { keys = "w", desc = "Write index" },
    stage_toggle_visual = { keys = { "-", "<space>" }, mode = "v", desc = "Stage/unstage selection" },
    stage_visual = { keys = "s", mode = "v", desc = "Stage selection" },
    unstage_visual = { keys = "u", mode = "v", desc = "Unstage selection" },
    discard_visual = { keys = { "x", "d" }, mode = "v", desc = "Discard selection" },
    menu_commit = { keys = "c", desc = "Open commit menu" },
    menu_diff = { keys = "d", desc = "Open diff menu" },
    menu_branch = { keys = "b", desc = "Open branch menu" },
    menu_push = { keys = "P", desc = "Open push menu" },
    menu_fetch = { keys = "f", desc = "Open fetch menu" },
    menu_pull = { keys = "p", desc = "Open pull menu" },
    menu_forge = { keys = "N", desc = "Open forge menu" },
    menu_stash = { keys = "z", desc = "Open stash menu" },
    menu_cherry_pick = { keys = "A", desc = "Open cherry-pick menu" },
  },
  commit_log = {
    exit = { keys = { "q", "<esc>" }, desc = "Close window" },
    focus_file_tree = { keys = { "K", "<tab>" }, desc = "Move to file tree" },
    focus_file_tree_disable = { keys = "J", desc = "No-op: disable mirror pane move" },
    quick_jump_down = { keys = "j", desc = "Jump down (2 lines)" },
    quick_jump_up = { keys = "k", desc = "Jump up (2 lines)" },
    copy_oid = { keys = "yy", desc = "Copy commit id" },
    copy_oid_clipboard = { keys = "yc", desc = "Copy commit id to clipboard" },
  },
  patch_unstaged = {
    exit = { keys = { "q", "<esc>" }, desc = "Close window" },
    menu_commit = { keys = "c", desc = "Open commit menu" },
    menu_branch = { keys = "b", desc = "Open branch menu" },
    focus_file_tree = { keys = "h", desc = "Move to file tree" },
    focus_staged = { keys = "l", desc = "Move to staged patch" },
    toggle_off = { keys = "=", desc = "Turn off patch view" },
    stage_hunk = { keys = { "-", "s" }, desc = "Stage hunk" },
    discard_hunk = { keys = { "d", "x" }, desc = "Discard hunk" },
    stage_visual = { keys = { "-", "s" }, mode = "v", desc = "Stage selection" },
    discard_visual = { keys = { "d", "x" }, mode = "v", desc = "Discard selection" },
    jump_file = { keys = "<cr>", desc = "Jump to file" },
  },
  patch_staged = {
    exit = { keys = { "q", "<esc>" }, desc = "Close window" },
    menu_commit = { keys = "c", desc = "Open commit menu" },
    menu_branch = { keys = "b", desc = "Open branch menu" },
    focus_file_tree = { keys = "h", desc = "Move to file tree" },
    toggle_off = { keys = "=", desc = "Turn off patch view" },
    unstage_hunk = { keys = { "-", "u" }, desc = "Unstage hunk" },
    unstage_visual = { keys = { "-", "u" }, mode = "v", desc = "Unstage selection" },
    jump_file = { keys = "<cr>", desc = "Jump to file" },
  },
  rebase = {
    exit = { keys = { "<esc>", "q" }, desc = "Abort / close" },
    start = { keys = "<cr>", desc = "Start rebase" },
    continue = { keys = "<cr>", desc = "Continue rebase" },
    drop = { keys = { "x", "d" }, desc = "Drop commit" },
    break_commit = { keys = "b", desc = "Break" },
    edit = { keys = "e", desc = "Edit commit" },
    squash = { keys = "s", desc = "Squash commit" },
    fixup = { keys = "f", desc = "Fixup commit" },
    reword = { keys = { "r", "w" }, desc = "Reword commit" },
    pick = { keys = "p", desc = "Pick commit" },
    squash_visual = { keys = "s", mode = "v", desc = "Squash commits" },
    fixup_visual = { keys = "f", mode = "v", desc = "Fixup commits" },
    move_down = { keys = { "gj", "<C-j>" }, desc = "Move commit down" },
    move_up = { keys = { "gk", "<C-k>" }, desc = "Move commit up" },
    quick_jump_down = { keys = "j", desc = "Jump down (2 lines)" },
    quick_jump_up = { keys = "k", desc = "Jump up (2 lines)" },
    quick_jump_down_visual = { keys = "j", mode = "v", desc = "Jump down (2 lines)" },
    quick_jump_up_visual = { keys = "k", mode = "v", desc = "Jump up (2 lines)" },
  },
  graph_log = {
    exit = { keys = { "q", "<esc>" }, desc = "Close window" },
    refresh = { keys = "r", desc = "Refresh" },
    focus_branch = { keys = "h", desc = "Move to branch view" },
    quick_jump_down = { keys = "j", desc = "Jump down (2 lines)" },
    quick_jump_up = { keys = "k", desc = "Jump up (2 lines)" },
    copy_oid = { keys = "yy", desc = "Copy commit id" },
    copy_oid_clipboard = { keys = "yc", desc = "Copy commit id to clipboard" },
  },
  graph_branch = {
    exit = { keys = { "q", "<esc>" }, desc = "Close window" },
    refresh = { keys = "r", desc = "Refresh" },
    focus_log = { keys = { "l", "<cr>", "<space>" }, desc = "Move to commit log" },
  },
  graph_select = {
    select_commit = { keys = { "<cr>", "<space>" }, desc = "Select commit" },
    select_branch = { keys = { "<cr>", "<space>" }, desc = "Select branch" },
  },
  diff = {
    exit = { keys = { "q", "<esc>" }, desc = "Close window" },
    focus_pane = { keys = { "l", "<cr>" }, desc = "Focus diff pane" },
    stage_file = { keys = "s", desc = "Stage file" },
    unstage_file = { keys = "u", desc = "Unstage file" },
    stage_toggle = { keys = { "-", "<space>" }, desc = "Stage/unstage file" },
    refresh = { keys = "r", desc = "Refresh" },
  },
  stash_list = {
    exit = { keys = { "q", "<esc>" }, desc = "Close window" },
    apply = { keys = "a", desc = "Apply stash" },
    pop = { keys = "p", desc = "Pop stash" },
    drop = { keys = "d", desc = "Drop stash" },
  },
  pick = {
    exit = { keys = { "<esc>", "<C-c>" }, mode = "i", desc = "Close window" },
    next_item = { keys = "<C-n>", mode = "i", desc = "Move to next item" },
    prev_item = { keys = "<C-p>", mode = "i", desc = "Move to previous item" },
  },
  input = {
    exit = { keys = { "q", "<esc>" }, desc = "Cancel input" },
    exit_insert = { keys = "<C-c>", mode = "i", desc = "Cancel input" },
    enter = { keys = "<cr>", desc = "Confirm input" },
    enter_insert = { keys = "<C-cr>", mode = "i", desc = "Confirm input" },
  },
  confirm = {
    exit = { keys = { "q", "n", "<esc>" }, desc = "No / close" },
    move_no = { keys = "l", desc = "Move to No" },
    move_yes = { keys = "h", desc = "Move to Yes" },
    toggle = { keys = "<tab>", desc = "Toggle Yes/No" },
    yes = { keys = "y", desc = "Confirm Yes" },
    yes_enter = { keys = "<cr>", desc = "Confirm Yes" },
  },
  blame = {
    exit = { keys = { "q", "<esc>" }, desc = "Close window" },
    next_hunk = { keys = { "J", "]c" }, desc = "Next hunk" },
    prev_hunk = { keys = { "K", "[c" }, desc = "Previous hunk" },
  },
  blame_file = {
    exit = { keys = { "q", "<esc>" }, desc = "Close window" },
    show_detail = { keys = "c", desc = "Toggle blame hunk detail" },
  },
  blame_popup = {
    exit = { keys = { "q", "<esc>" }, desc = "Close blame detail" },
  },
  patch = {
    next_hunk = { keys = "J", desc = "Next hunk" },
    prev_hunk = { keys = "K", desc = "Previous hunk" },
  },
}

---Resolves the effective key binding for an action.
---@param group string View group name.
---@param action string Action id.
---@return Fugit2KeymapDef?
function M.get(group, action)
  local defs = M.defaults[group]
  return defs and defs[action] or nil
end

---Resolves the effective key(s) for an action given user overrides.
---@param group string View group name.
---@param action string Action id.
---@param user table<string, string|string[]|false|"">? User overrides for the group.
---@return string|string[]|false|nil  Effective keys; `false` means disabled.
function M.resolve_keys(group, action, user)
  user = user or {}
  local keys = user[action]
  if keys == nil then
    local def = M.get(group, action)
    if def then
      keys = def.keys
    end
  end
  return keys
end

---Binds every action in a group to a view.
---
---Iterates `M.defaults[group]`. The effective keys come from `user[action]` when set
---(`false` disables the mapping entirely, `""` maps it to a no-op), otherwise the
---default. Actions with no handler in `handlers` are skipped.
---@param view table A NUI view exposing `map(mode, keys, fn, opts)`.
---@param group string View group name.
---@param handlers Fugit2KeymapHandlers action -> handler function or "" (no-op).
---@param user table<string, string|string[]|false|"">? User overrides for the group.
---@param opts table? Mapping options, defaults to `{ noremap = true, nowait = true }`.
function M.bind(view, group, handlers, user, opts)
  user = user or {}
  opts = opts or { noremap = true, nowait = true }

  local defs = M.defaults[group]
  if not defs then
    return
  end

  for action, def in pairs(defs) do
    local handler = handlers[action]
    if handler ~= nil then
      local keys = user[action]
      if keys == nil then
        keys = def.keys
      elseif keys == "" then
        keys = def.keys
        handler = ""
      end

      if keys ~= false and keys ~= nil then
        view:map(def.mode or "n", keys, handler, opts)
      end
    end
  end
end

---Binds every action in a group to a raw buffer via `nui.utils.keymap.set`.
---Used by views that do not mount NUI components (e.g. blame split view).
---@param bufnr integer Target buffer.
---@param group string View group name.
---@param handlers Fugit2KeymapHandlers action -> handler function or "" (no-op).
---@param user table<string, string|string[]|false|"">? User overrides for the group.
---@param opts table? Mapping options, defaults to `{ noremap = true, nowait = true }`.
function M.bind_buf(bufnr, group, handlers, user, opts)
  user = user or {}
  opts = opts or { noremap = true, nowait = true }
  local keymap = require "nui.utils.keymap"

  local defs = M.defaults[group]
  if not defs then
    return
  end

  for action, def in pairs(defs) do
    local handler = handlers[action]
    if handler ~= nil then
      local keys = user[action]
      if keys == nil then
        keys = def.keys
      elseif keys == "" then
        keys = def.keys
        handler = ""
      end

      if keys ~= false and keys ~= nil then
        keymap.set(bufnr, def.mode or "n", keys, handler, opts)
      end
    end
  end
end

---Returns all keymap defs for a group, used by the help menu.
---@param group string View group name.
---@return table<string, Fugit2KeymapDef>?  action -> def
function M.defs(group)
  return M.defaults[group]
end

return M
