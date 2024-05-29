local M = {}

M.link_colors = {
  Fugit2Header = "Label",
  Fugit2ObjectId = "Comment",
  Fugit2Author = "Tag",
  Fugit2HelpHeader = "Label",
  Fugit2HelpTag = "Tag",
  Fugit2Heading = "PreProc",
  Fugit2UntrackedHeading = "PreCondit",
  Fugit2UnstagedHeading = "Macro",
  Fugit2StagedHeading = "Include",
  Fugit2MessageHeading = "diffAdded",
  Fugit2Modifier = "Type",
  Fugit2Ignored = "Ignore",
  Fugit2Unstaged = "diffRemoved",
  Fugit2Staged = "diffAdded",
  Fugit2Modified = "Constant",
  Fugit2Unchanged = "",
  Fugit2Untracked = "Error",
  Fugit2Instruction = "Type",
  Fugit2Stop = "Function",
  Fugit2Hash = "Identifier",
  Fugit2SymbolicRef = "Function",
  Fugit2Count = "Number",
  Fugit2Insertions = "diffAdded",
  Fugit2Deletions = "diffRemoved",
  Fugit2Match = "Type",
  Fugit2WindowHelp = "Comment",
  Fugit2MenuHead = "Function",
  Fugit2MenuKey = "PreProc",
  Fugit2MenuArgOff = "Comment",
  Fugit2MenuArgOn = "Number",
  Fugit2BranchHead = "Type",
  Fugit2FloatTitle = "@parameter",
  Fugit2RebasePick = "diffAdded", -- green
  Fugit2RebaseDrop = "diffRemoved", -- red
  Fugit2RebaseSquash = "Type", -- yellow
  Fugit2BlameDate = "Comment",
  Fugit2BlameBorder = "Comment",
  Fugit2Branch1 = "diffAdded", -- green
  Fugit2Branch2 = "@field", --dark blue
  Fugit2Branch3 = "Type", -- yellow
  Fugit2Branch4 = "PreProc", -- orange
  Fugit2Branch5 = "Error", --red
  Fugit2Branch6 = "Keyword", -- violet
  Fugit2Branch7 = "@parameter", -- blue
}

M.colors = {
  Fugit2Branch8 = { ctermfg = "magenta", fg = "green1" },
  Fugit2Branch9 = { ctermfg = "green", fg = "yellow1" },
}

---Sets highlight groups
---@param ns_id integer
function M.set_hl(ns_id)
  for hl_group, link in pairs(M.link_colors) do
    vim.api.nvim_set_hl(ns_id, hl_group, {
      link = link,
      default = true,
    })
  end

  for hl_group, color in pairs(M.colors) do
    vim.api.nvim_set_hl(ns_id, hl_group, color)
  end

  --reverse for tagging
  for i = 1, 9 do
    local link = M.link_colors["Fugit2Branch" .. i]
    local hl_group = link and vim.api.nvim_get_hl(0, { name = link }) or M.colors["Fugit2Branch" .. i]
    vim.api.nvim_set_hl(ns_id, "Fugit2Tag" .. i, {
      fg = hl_group.fg,
      bg = hl_group.bg,
      ctermfg = hl_group.ctermfg,
      ctermbg = hl_group.ctermbg,
      reverse = true,
      default = true,
    })
  end

  -- Blame time heatmap
  -- get from github ui
  local blame_date_heat = {
    "#3d1300",
    "#5a1e02",
    "#762d0a",
    "#9b4215",
    "#bd561d",
    "#db6d28",
    "#f0883e",
    "#f0883e",
    "#ffc680",
    "#ffdfb6",
  }
  for i, color in ipairs(blame_date_heat) do
    vim.api.nvim_set_hl(ns_id, "Fugit2BlameAge" .. i, {
      fg = color,
    })
  end
end

return M
