vim.api.nvim_create_user_command("FgStatus", require("fugit2").git_status, {})
vim.api.nvim_create_user_command("FgGraph", require("fugit2").git_graph, {})
