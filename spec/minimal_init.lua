--- Run this file before you run unittests.
--- 依存プラグインはないので、runtimepath の設定のみ行う。

vim.opt.rtp:append(".")

vim.cmd("runtime plugin/bunsetsu.lua")

require("bunsetsu._core.configuration").initialize_data_if_needed()
