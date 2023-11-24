-- Fugit2 main module file
local colors = require "fugit2.view.colors"

---@class Config
---@field opt string Default config option
local config = {
  opt = "Hello!",
}


---@class Fugit2Module
local M = {}

---@type number
M.namespace = 0

---@type Config
M.config = config


---@param args Config?
-- Usually configurations can be merged, accepting outside params and
-- some validation here.
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  -- Validate

  if M.namespace == 0 then
    M.namespace = vim.api.nvim_create_namespace("Fugit2")
    colors.set_hl(0)
  end
end


M.hello = function()
  -- module.my_first_function()
  return "Hello World!"
end

return M
