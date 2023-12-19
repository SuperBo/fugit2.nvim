local M = {}


M.link_colors = {
  Fugit2Header            = "Label",
  Fugit2ObjectId          = "Comment",
  Fugit2Author            = "Tag",
  Fugit2HelpHeader        = "Label",
  Fugit2HelpTag           = "Tag",
  Fugit2Heading           = "PreProc",
  Fugit2UntrackedHeading  = "PreCondit",
  Fugit2UnstagedHeading   = "Macro",
  Fugit2StagedHeading     = "Include",
  Fugit2MessageHeading    = "diffAdded",
  Fugit2Modifier          = "Type",
  Fugit2Ignored           = "Ignore",
  Fugit2Unstaged          = "diffRemoved",
  Fugit2Staged            = "diffAdded",
  Fugit2Modified          = "Constant",
  Fugit2Unchanged         = "",
  Fugit2Untracked         = "Error",
  Fugit2Instruction       = "Type",
  Fugit2Stop              = "Function",
  Fugit2Hash              = "Identifier",
  Fugit2SymbolicRef       = "Function",
  Fugit2Count             = "Number",
  Fugit2WindowHelp        = "Comment",
  Fugit2MenuHead          = "Function",
  Fugit2MenuKey           = "Keyword",
  Fugit2BranchHead        = "Type",
}

M.colors = {
}


---Sets highlight groups
---@param ns_id integer
function M.set_hl(ns_id)
  for hl_group, link in pairs(M.link_colors) do
    vim.api.nvim_set_hl(ns_id, hl_group, {
      link = link,
      default = true
    })
  end

  for hl_group, color in pairs(M.colors) do
    vim.api.nvim_set_hl(ns_id, hl_group, {
      fg = color,
      default = true
    })
  end
end


return M
