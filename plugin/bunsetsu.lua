if vim.fn.has("nvim-0.11") == 0 then
  vim.api.nvim_err_writeln("bunsetsu.nvim requires Neovim 0.11 or later")
  return
end

--- All `bunsetsu` command definitions.

local configuration = require("bunsetsu._core.configuration")

configuration.initialize_data_if_needed()

-- コマンド定義
vim.api.nvim_create_user_command("BunsetsuSplit", function(opts)
  require("bunsetsu").split_lines(opts.line1, opts.line2)
end, { range = true, nargs = 0, desc = "Split current range into bunsetsu" })

vim.api.nvim_create_user_command("BunsetsuVibratoSetup", function(opts)
  require("bunsetsu").vibrato_setup({
    flavor = opts.args ~= "" and opts.args or nil,
    force = opts.bang,
  })
end, {
  nargs = "?",
  bang = true,
  desc = "Automatically install the Vibrato backend (build CLI + download dictionary)",
  complete = function()
    return { "ipadic", "unidic-mecab", "unidic-cwj", "jumandic", "naist-jdic" }
  end,
})
