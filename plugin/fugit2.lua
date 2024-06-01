vim.api.nvim_create_user_command("Fugit2", require "fugit2".git_status, {
  desc = "Open Fugit2 main popup."
})
vim.api.nvim_create_user_command("Fugit2Graph", require "fugit2".git_graph, {
  desc = "Open Fugit2 git graph popup."
})
vim.api.nvim_create_user_command("Fugit2Diff", require "fugit2".git_diff, {
  desc = "Open Fugit2 diff view tab.",
  nargs = "?"
})
vim.api.nvim_create_user_command("Fugit2Blame", require "fugit2".git_blame, {
  desc = "Open Fugit2Blame.",
  nargs = "?"
})
