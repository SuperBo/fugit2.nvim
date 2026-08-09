-- Fugit2 config module

---@class FileTreeActions
---@field commit string?
---@field diff string?
---@field branch string?
---@field push string?
---@field fetch string?
---@field pull string?
---@field forge string?
---@field stash string?
---@field cherry_pick string?

---@class FileTreeMaps
---@field menu FileTreeActions
---@field direct FileTreeActions?

---@class Fugit2Config
---@field width integer|string main popup width
---@field max_width integer|string expand popup width
---@field min_width integer file view width when expand patch view
---@field content_width integer file view content width
---@field height integer|string main file popup height
---@field show_patch boolean show patch for active file when open fugit2 main window
---@field libgit2_path string? path to libgit2 lib if not set via environments
---@field gpgme_path string? path to gpgme lib, default: "gpgme"
---@field external_diffview boolean whether to use external diffview.nvim or Fugit2 implementation
---@field blame_priority integer priority of blame virtual text
---@field blame_info_width integer width of blame hunk detail popup
---@field blame_info_height integer height of blame hunk detail popup
---@field command_timeout integer timeout in milisecond of command like git pull / git push
---@field colorscheme string? custom colorscheme specification
---@field file_tree_maps FileTreeMaps keymaps for file tree (deprecated, use keymaps)
---@field keymaps table<string, table<string, string|string[]|false>> keymaps for all views
local DEFAULT_CONFIG = {
  width = 100,
  min_width = 50,
  content_width = 60,
  max_width = "80%",
  height = "60%",
  external_diffview = false,
  blame_priority = 1,
  blame_info_height = 10,
  blame_info_width = 60,
  show_patch = false,
  command_timeout = 15000,
  file_tree_maps = {
    menu = {
      commit = "c",
      diff = "d",
      branch = "b",
      push = "P",
      fetch = "f",
      pull = "p",
      forge = "N",
      stash = "z",
      cherry_pick = "A",
    },
  },
}

local M = {}
M.config = DEFAULT_CONFIG

-- Legacy file_tree_maps action names to registry `menu_*` action ids.
local FILE_TREE_MENU_ACTIONS = {
  commit = "menu_commit",
  diff = "menu_diff",
  branch = "menu_branch",
  push = "menu_push",
  fetch = "menu_fetch",
  pull = "menu_pull",
  forge = "menu_forge",
  stash = "menu_stash",
  cherry_pick = "menu_cherry_pick",
}

-- Usually configurations can be merged,
-- accepting outside params and some validation here.
function M.merge(args)
  -- TODO: validate args
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  -- Backward compatibility: translate the deprecated file_tree_maps.menu into the
  -- unified keymaps.file_tree.<menu_*action> namespace so existing configs keep
  -- working. New keymaps entries take precedence.
  M.config.keymaps = M.config.keymaps or {}
  M.config.keymaps.file_tree = M.config.keymaps.file_tree or {}

  local legacy_menu = args and args.file_tree_maps and args.file_tree_maps.menu or {}
  for action, key in pairs(legacy_menu) do
    local registry_action = FILE_TREE_MENU_ACTIONS[action]
    if registry_action and M.config.keymaps.file_tree[registry_action] == nil then
      M.config.keymaps.file_tree[registry_action] = key
    end
  end

  return M.config
end

-- Returns Fugit2 whole config.
---@return Fugit2Config
function M.get()
  return M.config
end

-- Returns the keymaps config for a group, always a table.
---@param group string? view group name
---@return table<string, string|string[]|false>
function M.get_keymaps(group)
  local keymaps = M.config.keymaps or {}
  if group then
    return keymaps[group] or {}
  end
  return keymaps
end

-- Returns Fugit2 config setting as string
---@param setting string setting key
---@return string?
function M.get_string(setting)
  return tostring(M.config[setting])
end

-- Returns Fugit2 config setting as number
---@param setting "blame_info_height"|"blame_info_width"|"blame_priority"|"content_width"|"min_width"|"command_timeout" setting key
---@return number?
function M.get_number(setting)
  return tonumber(M.config[setting])
end

-- Returns Fugit2 config setting as boolean
---@param setting "show_patch"
---@return boolean
function M.get_bool(setting)
  if M.config[setting] then
    return true
  else
    return false
  end
end

return M
