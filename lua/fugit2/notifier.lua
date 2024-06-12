---@class Fugit2Notifier
local M = {}

-- Notify info message
---@param msg string
function M.info(msg)
  vim.notify("[Fugit2] " .. msg, vim.log.levels.INFO)
end

-- Notify error message
---@param msg string
---@parm err integer?
function M.error(msg, err)
  local content = "[Fugit2] " .. msg
  if err ~= nil and err ~= 0 then
    content = content .. string.format(".\nError code %d", err)
  end
  vim.notify(content, vim.log.levels.ERROR)
end

-- Notify warning message
function M.warn(msg)
  vim.notify("[Fugit2] " .. msg, vim.log.levels.WARN)
end

return M
