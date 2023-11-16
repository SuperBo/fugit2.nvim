local M = {}


M.colors = {
  fugit2Header            = "Label",
  fugit2HelpHeader        = "Label",
  fugit2HelpTag           = "Tag",
  fugit2Heading           = "PreProc",
  fugit2UntrackedHeading  = "PreCondit",
  fugit2UnstagedHeading   = "Macro",
  fugit2StagedHeading     = "Include",
  fugit2Modifier          = "Type",
  fugit2UntrackedModifier = "StorageClass",
  fugit2UnstagedModifier  = "Structure",
  fugit2StagedModifier    = "Typedef",
  fugit2Instruction       = "Type",
  fugit2Stop              = "Function",
  fugit2Hash              = "Identifier",
  fugit2SymbolicRef       = "Function",
  fugit2Count             = "Number",
}


---Sets highlight groups
---@param namespace number
function M.set_hl(namespace)
  for hl_group, link in pairs(M.colors) do
    vim.api.nvim_set_hl(namespace, hl_group, {
      link = link,
      default = true,
    })
  end
end


return M
