---Module contains reimplementation of git rebase
---Extends libgit2 git rebase with support for
---SQUASH AND FIXUP


---@module "fugit2.core.git_rebase"
local M = {}

---@enum FUGIT2_GIT_REBASE_ACTION
M.GIT_REBASE_ACTION = {
  PICK   = 0,
  REWORD = 1,
  EDIT   = 2,
  SQUASH = 3,
  FIXUP  = 4,
  EXEC   = 5,
  DROP   = 6,
  BREAK  = 7,
  BASE   = 8,
}


-- Fugit2 Git In-memory rebase
---@class Fugit2GitRebase
---@field repo GitRepository
---@field index GitIndex In memory index
---@field commit GitCommit? Last commit
---@field onto_id GitObjectId
---@field onto_name string
---@field operations FUGIT2_GIT_REBASE_ACTION[]

return M
