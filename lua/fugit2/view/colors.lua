local M = {}


M.link_colors = {
  Fugit2Header           = "Label",
  Fugit2ObjectId         = "Comment",
  Fugit2Author           = "Tag",
  Fugit2HelpHeader       = "Label",
  Fugit2HelpTag          = "Tag",
  Fugit2Heading          = "PreProc",
  Fugit2UntrackedHeading = "PreCondit",
  Fugit2UnstagedHeading  = "Macro",
  Fugit2StagedHeading    = "Include",
  Fugit2MessageHeading   = "diffAdded",
  Fugit2Modifier         = "Type",
  Fugit2Ignored          = "Ignore",
  Fugit2Unstaged         = "diffRemoved",
  Fugit2Staged           = "diffAdded",
  Fugit2Modified         = "Constant",
  Fugit2Unchanged        = "",
  Fugit2Untracked        = "Error",
  Fugit2Instruction      = "Type",
  Fugit2Stop             = "Function",
  Fugit2Hash             = "Identifier",
  Fugit2SymbolicRef      = "Function",
  Fugit2Count            = "Number",
  Fugit2WindowHelp       = "Comment",
  Fugit2MenuHead         = "Function",
  Fugit2MenuKey          = "Keyword",
  Fugit2MenuArgOff       = "Comment",
  Fugit2MenuArgOn        = "Number",
  Fugit2BranchHead       = "Type",
  Fugit2FloatTitle       = "@parameter",
  Fugit2Branch1          = "diffAdded", -- green
  Fugit2Branch2          = "@field", --dark blue
  Fugit2Branch3          = "Type", -- yellow
  Fugit2Branch4          = "PreProc", -- orange
  Fugit2Branch5          = "Error", --red
  Fugit2Branch6          = "Keyword", -- violet
  Fugit2Branch7          = "@parameter", -- blue
}

M.colors = {
  -- Fugit2Branch1 = { ctermfg = "magenta", fg = "green1" },
  -- Fugit2Branch2 = { ctermfg = "green",   fg = "yellow1" },
  -- Fugit2Branch3 = { ctermfg = "yellow",  fg = "orange1" },
  -- Fugit2Branch4 = { ctermfg = "cyan",    fg = "greenyellow" },
  -- Fugit2Branch5 = { ctermfg = "red",     fg = "springgreen1" },
  -- Fugit2Branch6 = { ctermfg = "yellow",  fg = "cyan1" },
  -- Fugit2Branch7 = { ctermfg = "green",   fg = "slateblue1" },
  -- Fugit2Branch8 = { ctermfg = "cyan",    fg = "magenta1" },
  -- Fugit2Branch9 = { ctermfg = "magenta", fg = "purple1" },
  Fugit2Branch8 = { ctermfg = "magenta", fg = "green1" },
  Fugit2Branch9 = { ctermfg = "green",   fg = "yellow1" },
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
    vim.api.nvim_set_hl(ns_id, hl_group, color)
  end
end


return M
