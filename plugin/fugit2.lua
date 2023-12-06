vim.api.nvim_create_user_command("Fugit2", require("fugit2").git_status, {})
vim.api.nvim_create_user_command("Fugit2Graph", require("fugit2").git_graph, {})
