local git2 = require "fugit2.git2"
local NuiLayout = require "nui.layout"
local RebaseView = require "fugit2.view.git_rebase"
local uv = vim.loop
local fugit2 = require "fugit2"

local repo = git2.Repository.open("/Users/ynguyen/Workspace/fugit2.nvim", false)
local namespace = vim.api.nvim_create_namespace("helloFu")
-- if repo then
--   local view = RebaseView(namespace, repo, nil, {
--     upstream = "4d17aa3d"
--   })
--
--   view:mount()
-- end
--

if repo then
  fugit2.git_diff()
end
