-- Fugit main module file
local module = require "fugit2.module"

---@class Config
---@field opt string Default config option
local config = {
  opt = "Hello!",
}

---@class MyModule
local M = {}

---@type Config
M.config = config

---@param args Config?
-- Usually configurations can be merged, accepting outside params and
-- some validation here.
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
end

M.hello = function()
  -- module.my_first_function()
  return "Hello World!"
end

return M
