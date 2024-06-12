-- Fugit2 config module

---@class Fugit2Config
---@field width integer|string main popup width
---@field max_width integer|string expand popup width
---@field min_width integer file view width when expand patch view
---@field content_width integer file view content width
---@field height integer|string main file popup height
---@field libgit2_path string? path to libgit2 lib if not set via environments
---@field gpgme_path string? path to gpgme lib, default: "gpgme"
---@field external_diffview boolean whether to use external diffview.nvim or Fugit2 implementation
---@field blame_priority integer priority of blame virtual text
---@field blame_info_width integer width of blame hunk detail popup
---@field blame_info_height integer height of blame hunk detail popup
---@field colorscheme string? custom colorscheme specification
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
}

local M = {}
M.config = DEFAULT_CONFIG

-- Usually configurations can be merged,
-- accepting outside params and some validation here.
function M.merge(args)
  -- TODO: validate args
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  return M.config
end

-- Returns Fugit2 whole config.
---@return Fugit2Config
function M.get()
  return M.config
end

-- Returns Fugit2 config setting as string
---@param setting string setting key
---@return string?
function M.get_string(setting)
  return tostring(M.config[setting])
end

-- Returns Fugit2 config setting as number
---@param setting "blame_info_height"|"blame_info_width"|"blame_priority"|"content_width"|"min_width" setting key
---@return number?
function M.get_number(setting)
  return tonumber(M.config[setting])
end

return M
