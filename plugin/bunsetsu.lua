--- All `bunsetsu` command definitions.

local configuration = require("bunsetsu._core.configuration")

configuration.initialize_data_if_needed()

-- コマンド定義
vim.api.nvim_create_user_command("BunsetsuSplit", function(opts)
  require("bunsetsu").split_lines(opts.line1, opts.line2)
end, { range = true, nargs = 0, desc = "Split current range into bunsetsu" })
