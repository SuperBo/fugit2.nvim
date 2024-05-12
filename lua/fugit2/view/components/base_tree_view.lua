---Base class for File Tree View and Source Tree View

---@enum Fugit2IndexAction
local IndexAction = {
  ADD = 1,
  RESET = 2,
  ADD_RESET = 3,
  DISCARD = 4,
}

local GitTreeBase = {
  IndexAction = IndexAction,
}

return GitTreeBase
