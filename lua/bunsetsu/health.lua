--- `:checkhealth bunsetsu` の実装。

local M = {}

function M.check()
  local ok, _ = pcall(require, "bunsetsu")
  if not ok then
    vim.health.error("bunsetsu.nvim の読み込みに失敗しました。")
    return
  end

  vim.health.start("bunsetsu.nvim")

  -- lua-utf8 確認 (任意。無い場合はバイト単位の後方処理にフォールバック)
  local ok_utf8 = pcall(require, "lua-utf8")
  if ok_utf8 then
    vim.health.ok("lua-utf8 読み込みOK")
  else
    vim.health.info(
      "lua-utf8 がありません (任意。spider の後方移動 (b/ge) がバイト単位のフォールバックになります)"
    )
  end

  -- Vibrato 確認
  local config = require("bunsetsu._core.configuration")
  local dict = config.DATA.vibrato.dict
  local cmd = config.DATA.vibrato.cmd or "vibrato"
  if dict and dict ~= "" then
    if vim.fn.filereadable(dict) == 1 then
      vim.health.ok(("Vibrato 辞書: %s"):format(dict))
    else
      vim.health.error(("Vibrato 辞書が見つかりません: %s"):format(dict))
    end
    if vim.fn.executable(cmd) == 1 then
      vim.health.ok(("Vibrato コマンド: %s"):format(cmd))
    else
      vim.health.error(("Vibrato コマンドが見つかりません: %s"):format(cmd))
    end
  else
    vim.health.warn("Vibrato 辞書が未設定です")
  end

  -- 分割テスト
  local vibrato = require("bunsetsu._commands.vibrato")
  local words, infos = vibrato.tokenize_detailed("これは文章です。")
  if #words > 0 then
    local parts = {}
    for i, w in ipairs(words) do
      local lemma = infos[i] and infos[i].lemma or ""
      parts[#parts + 1] = string.format("%s(%s)", w, lemma)
    end
    vim.health.ok(("Vibrato 分割OK: %s"):format(table.concat(parts, " ")))
  else
    vim.health.warn("Vibrato が空の結果を返しました")
  end
end

return M
