local color = require "fugit2.hl.color"

local M = {}

M.link_colors = {
  Fugit2Header = "Label",
  Fugit2ObjectId = "Comment",
  Fugit2Author = "Tag",
  Fugit2AuthorEmail = "Label",
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
  Fugit2BlameDate = "Constant",
  Fugit2BlameBorder = "Comment",
  Fugit2GraphDate = "Type",
  Fugit2Branch1 = "diffAdded", -- green
  Fugit2Branch2 = "DiagnosticInfo", --dark blue
  Fugit2Branch3 = "Type", -- yellow
  Fugit2Branch4 = "PreProc", -- orange
  Fugit2Branch5 = "Error", --red
  Fugit2Branch6 = "Keyword", -- violet
  Fugit2Branch7 = "Identifier", -- blue/white
}

M.colors = {
  Fugit2Branch8 = { ctermfg = "magenta", fg = "green1" },
  Fugit2Branch9 = { ctermfg = "green", fg = "yellow1" },
}

CYBERDREAM = {
  Fugit2MenuKey = "Special",
  Fugit2FloatTitle = "PreProc",
  Fugit2MenuArgOn = "ErrorMsg",
}

---Sets highlight groups
---@param ns_id integer
---@param colorscheme string?
function M.set_hl(ns_id, colorscheme)
  -- small tweak for cyberdream
  if colorscheme == "cyberdream" then
    local link_colors = M.link_colors
    for group, hl in pairs(link_colors) do
      if hl == "diffAdded" then
        link_colors[group] = "DiffAdd"
      elseif hl == "diffRemoved" then
        link_colors[group] = "DiffDelete"
      end
    end

    M.link_colors = vim.tbl_deep_extend("force", link_colors, CYBERDREAM)
  end

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
  -- default base get from catppuccin
  local blame_base = "#1e66f5"
  local blame_text = "#4c4f69"

  local blame_latest = "Todo" -- Todo
  local blame_base_hl = vim.api.nvim_get_hl(0, { name = blame_latest })
  if blame_base_hl then
    if blame_base_hl.bg then
      blame_text = blame_base_hl.fg
      blame_base = blame_base_hl.bg
    elseif blame_base_hl.fg then
      blame_base = blame_base_hl.fg
      blame_text = blame_base_hl.bg
    end
  end

  local blame_palette = color.generate_palette(blame_base, 10, 0.1)

  for i, c in ipairs(blame_palette) do
    vim.api.nvim_set_hl(ns_id, "Fugit2BlameAge" .. i, {
      fg = blame_text,
      bg = c,
    })
  end
end

return M
