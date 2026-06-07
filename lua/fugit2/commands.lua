--- Contains logic for G/Git command. Purpose of these commands is support vim-fugitive commands.

local Path = require "plenary.path"
local git2 = require "fugit2.core.git2"
local notifier = require "fugit2.notifier"

---@class Fugit2GitCommands
local M = {}

---@alias GitBufferMode
---| ` "worktree" `# command is called from worktree
---| ` "index" `   # command is called from index
---| ` "blob" `    # command is called from blob history

-- Logic of Gwrite  command
-- writes to both the work tree and index versions of a file,
-- making it like git add when called from a work tree file and
-- like git checkout when called from the index or a blob in history.
---@param mode GitBufferMode
---@param repo GitRepository
function M.git_write(repo, mode)
  if mode ~= "worktree" then
    notifier.error "Only support worktree buffer now"
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local file_name = vim.api.nvim_buf_get_name(bufnr)
  local file_path = Path:new(file_name):make_relative(repo:workdir())

  local is_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
  -- Save file to disk first
  if is_modifiable and buftype == "" then
    vim.cmd.write(file_name)
  end

  local wt_status, _, err = repo:status_file(file_path)
  local wstatus = err == 0 and git2.status_char_dash(wt_status) or nil
  if err == 0 and (wstatus == "?" or wstatus == "T" or wstatus == "M" or wstatus == "U") then
    local index = repo:index()
    if index then
      err = index:add_bypath(file_path)
      if err ~= 0 then
        notifier.error("Error when adding " .. tostring(file_path), err)
      else
        notifier.info("Added " .. tostring(file_path))
      end
    end
  end
end

return M
