---flash.nvim 統合。
--
-- 事前計算済みの segment 一覧 (full.lua) を flash.nvim の matcher に渡す。
-- `require("bunsetsu._commands.plugins.flash").jump()` を呼ぶと
-- 文節(および ASCII 単語)の開始位置に flash のラベルが付く。
--
-- 使い方 (ユーザー設定側):
-- >lua
--   vim.keymap.set("n", "<leader>j", function()
--     require("bunsetsu._commands.plugins.flash").jump()
--   end, { desc = "Jump to bunsetsu" })
--

local config = require("bunsetsu._core.configuration")
local full = require("bunsetsu._commands.full")

local M = {}

---flash.nvim 用 matcher。バッファ全体の segment を FlashMatch 形式に変換する。
---flash.nvim の `require("flash").jump({ matcher = ... })` に渡す。
---
---@param model_name? string 分節モデル名 (省略時は設定値)
---@param opts? table matcher のオプション
---@return fun(win: number, state: table): table[]
function M.matcher(model_name, opts)
  local model = model_name or config.DATA.vibrato.dict or config.DATA.model
  return function(win)
    local buf = vim.api.nvim_win_get_buf(win)
    -- 現在のバッファのみを対象にする (マルチウィンドウは各ウィンドウの
    -- バッファが current でない場合はスキップ)
    if buf ~= vim.api.nvim_get_current_buf() then
      return {}
    end
    local matches = {}
    for _, fs in ipairs(full.full(model)) do
      local text = fs.text
      -- 空でない segment だけを対象にする
      if text ~= "" then
        table.insert(matches, {
          pos = { fs.lnum, fs.col - 1 },
          end_pos = { fs.lnum, fs.colend - 1 },
          text = text,
        })
      end
    end
    return matches
  end
end

---flash.nvim で文節ジャンプを実行する。
---@param opts? table require("flash").jump() に渡すオプション
function M.jump(opts)
  opts = opts or {}
  opts.matcher = opts.matcher or M.matcher()
  opts.label = opts.label or { after = true, before = false }
  opts.highlight = opts.highlight or { matches = true }
  -- flash.nvim が無い場合はエラーを通知
  local ok, flash = pcall(require, "flash")
  if not ok then
    vim.notify("flash.nvim is required for bunsetsu.flash.jump()", vim.log.levels.ERROR)
    return
  end
  flash.jump(opts)
end

return M
