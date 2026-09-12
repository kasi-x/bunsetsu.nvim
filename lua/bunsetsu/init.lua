--- All function(s) that can be called externally by other Lua modules.
---
--- If a function's signature here changes in some incompatible way, this
--- package must get a new **major** version.
---
--- bunsetsu.nvim は nvim-spider と flash.nvim の日本語文節拡張を提供する。

-- lua-utf8 があれば読み込んで spider からも使えるようにする (任意依存)。
-- 無い場合は文字単位でなくバイト単位の後方処理にフォールバックする
-- (vibrato.lua も spider と同じ挙動にフォールバックする)。
pcall(require, "lua-utf8")

local configuration = require("bunsetsu._core.configuration")
local full = require("bunsetsu._commands.full")
local lang = require("bunsetsu._core.lang")
local lemma = require("bunsetsu._core.lemma")
local util = require("bunsetsu._core.util")

local M = {}

configuration.initialize_data_if_needed()

--- Setup `bunsetsu.nvim`.
---
---@param opts? Bunsetsu.Config All extra customizations for this plugin.
function M.setup(opts)
  configuration.initialize_data_if_needed()
  configuration.resolve_data(opts)

  local augroup = vim.api.nvim_create_augroup("bunsetsu", { clear = true })

  -- 全文モード・一文モードのキャッシュをバッファ変更時に無効化。
  -- TextChanged 系は変更行のみ非同期で再分割する。
  -- 行数が変わる可能性のある操作 (undo/redo 等) では全破棄する。
  local model_name = function()
    return configuration.DATA.vibrato.dict
      or configuration.DATA.vaporetto.model
      or configuration.DATA.model
  end

  local function on_change(lnum)
    if lnum and lnum >= 1 then
      -- 変更行のみ非同期で再分割してキャッシュ更新。
      -- insert 中の連続変更 (TextChangedI) は debounce 設定 (ms) でまとめる
      util.debounce(augroup, function()
        full.refresh_line(model_name(), lnum)
      end, configuration.DATA.debounce)()
    else
      -- 全行キャッシュ破棄 (次回 full() 時に再構築)
      full.invalidate()
      vim.schedule(function()
        full.preload(model_name())
      end)
    end
  end

  -- バッファ行数の追跡 (変更で行数が変わった場合は全行再処理)
  local buf_line_counts = {}
  -- undo/redo の検出用 (seq_cur が変わったら undo/redo)
  local buf_undo_seqs = {}
  -- 日本語を含むバッファのみ追跡・再分割する。ASCII のみのバッファ
  -- (コード等) では、TextChanged ごとの undotree() 呼び出し (undo ツリー
  -- 全体の構築) が無駄に重いため、処理をすべてスキップする。
  -- フラグはバッファ進入時などのみ更新するため、ASCII バッファに入力した
  -- 日本語は次回進入時から対象になる (移動自体は full() が遅延計算するので
  -- 常に動作する)。
  local buf_is_jp = {}

  local function line_count_changed(buf)
    local cur = vim.api.nvim_buf_line_count(buf)
    local prev = buf_line_counts[buf]
    buf_line_counts[buf] = cur
    return prev ~= nil and prev ~= cur
  end

  -- undo/redo が行われたかどうかを seq_cur の変化で検出する。
  -- Neovim には Undo/Redo の autocmd イベントが無いため、これを追跡する。
  local function undo_occurred(buf)
    local cur = vim.fn.undotree().seq_cur
    local prev = buf_undo_seqs[buf]
    buf_undo_seqs[buf] = cur
    return prev ~= nil and prev ~= cur
  end

  ---バッファが日本語を含むかを更新する (先頭 500 行のみ走査)。
  local function refresh_jp_flag(buf)
    buf_is_jp[buf] = false
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 500, false)
    for _, line in ipairs(lines) do
      if lang.has_japanese(line) then
        buf_is_jp[buf] = true
        break
      end
    end
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if not buf_is_jp[buf] then
        return
      end
      if line_count_changed(buf) or undo_occurred(buf) then
        -- 行数が変わった、または undo/redo → 全行再処理
        on_change()
      else
        on_change(vim.fn.line("."))
      end
    end,
  })

  -- 品詞ハイライト用 namespace (highlight 設定が有効な場合に使用)
  local hl_namespace = vim.api.nvim_create_namespace("bunsetsu_highlight")
  local hl_enabled = configuration.DATA.highlight and configuration.DATA.highlight.enabled or false

  local function apply_highlight(buf)
    if not hl_enabled then
      return
    end
    local hl = require("bunsetsu._commands.highlight")
    hl.apply(buf, hl_namespace)
  end

  vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "BufEnter" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      refresh_jp_flag(buf)
      if not buf_is_jp[buf] then
        return
      end
      -- 全行キャッシュ破棄 + 全文をバックグラウンドで分割
      on_change()
      -- 品詞ハイライト (オプション)
      apply_highlight(buf)
      -- 行数・undo 位置の追跡をリセット
      buf_line_counts[buf] = vim.api.nvim_buf_line_count(buf)
      buf_undo_seqs[buf] = vim.fn.undotree().seq_cur
    end,
  })

  -- バッファ削除時に追跡テーブルを片付ける
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    pattern = "*",
    callback = function(event)
      buf_line_counts[event.buf] = nil
      buf_undo_seqs[event.buf] = nil
      buf_is_jp[event.buf] = nil
    end,
  })

  -- TextChanged でも変更行のハイライトを更新
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if hl_enabled and buf_is_jp[buf] then
        -- 全文再ハイライトは重いので、デバウンスして行単位で更新
        apply_highlight(buf)
      end
    end,
  })
end

---全文モードの segment 一覧を返す (flash matcher の基盤)。
---@return FullSegment[]
function M.full_segments()
  return full.full(configuration.DATA.vibrato.dict or configuration.DATA.vaporetto.model)
end

---現在バッファの形態素を品詞ごとにアンダーラインで色付けする。
---@param enabled? boolean 有効にするか。省略時はトグル。
function M.highlight(enabled)
  local hl = require("bunsetsu._commands.highlight")
  local ns = vim.api.nvim_create_namespace("bunsetsu_highlight")
  local buf = vim.api.nvim_get_current_buf()
  if enabled == false then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    return
  end
  hl.apply(buf, ns)
end

---指定範囲を文節区切りで分かち書きして置換する (:BunsetsuSplit 相当)。
---@param line1 number
---@param line2 number
function M.split_lines(line1, line2)
  local sep = configuration.DATA.splitsep
  local segment = require("bunsetsu._core.segment")
  for lnum = line1, line2 do
    local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
    local segcols
    if full.use_vibrato() then
      local vibrato = require("bunsetsu._commands.vibrato")
      local words, infos = vibrato.tokenize_detailed(line)
      local positions = segment.word_positions(line, words)
      segcols = segment.words_to_segments(words, positions, infos)
    else
      segcols = segment.split_line(configuration.DATA.model, line)
    end
    if #segcols > 0 then
      local segs = {}
      for i, sc in ipairs(segcols) do
        segs[i] = sc.segment
      end
      vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { table.concat(segs, sep) })
    end
  end
  full.invalidate()
end

---利用可能なバックエンドを返す。
---tinysegmenter は常に利用可能 (同梱)。辞書/モデル設定があれば
---vibrato / vaporetto も含む。
---@return string[]
function M.models()
  local ret = { "tinysegmenter" }
  local vibrato_dict = configuration.DATA.vibrato and configuration.DATA.vibrato.dict or ""
  local vaporetto_model = configuration.DATA.vaporetto and configuration.DATA.vaporetto.model or ""
  if vibrato_dict ~= "" then
    ret[#ret + 1] = "vibrato"
  end
  if vaporetto_model ~= "" then
    ret[#ret + 1] = "vaporetto"
  end
  return ret
end

---nvim-spider 用カスタムパターン関数を返す。
---設定に応じてバックエンドを自動選択する (vibrato 辞書 > vaporetto モデル >
---同梱 TinySegmenter)。
---
---spider.setup({ customPatterns = { patterns = { bunsetsu.pattern("bunsetsu") }, overrideDefault = false } })
---
---@param mode "word"|"bunsetsu" 境界の粒度。word=単語境界、bunsetsu=助詞を結合して文節に近い境界
---@return fun(line: string, searchOffset: number, key: string): number|false
function M.pattern(mode)
  mode = mode or "bunsetsu"
  local vibrato_dict = configuration.DATA.vibrato and configuration.DATA.vibrato.dict or ""
  local vaporetto_model = configuration.DATA.vaporetto and configuration.DATA.vaporetto.model or ""
  if vibrato_dict ~= "" then
    return require("bunsetsu._commands.vibrato").pattern(mode)
  elseif vaporetto_model ~= "" then
    return require("bunsetsu._commands.vaporetto").pattern(mode)
  end
  return require("bunsetsu._commands.spider").pattern
end

---Vaporetto バックエンドの spider カスタムパターン関数を返す。
---
---spider.setup({ customPatterns = { patterns = { bunsetsu.vaporetto_pattern("bunsetsu") }, overrideDefault = false } })
---
---@param mode "word"|"bunsetsu" 境界の粒度。word=単語境界、bunsetsu=助詞を結合して文節に近い境界
---@return fun(line: string, searchOffset: number, key: string): number|false
function M.vaporetto_pattern(mode)
  return require("bunsetsu._commands.vaporetto").pattern(mode or "bunsetsu")
end

---Vibrato バックエンドの spider カスタムパターン関数を返す。
---
---spider.setup({ customPatterns = { patterns = { bunsetsu.vibrato_pattern("bunsetsu") }, overrideDefault = false } })
---
---@param mode "word"|"bunsetsu" 境界の粒度。word=単語境界、bunsetsu=助詞を結合して文節に近い境界
---@return fun(line: string, searchOffset: number, key: string): number|false
function M.vibrato_pattern(mode)
  return require("bunsetsu._commands.vibrato").pattern(mode or "bunsetsu")
end

---次の文末へ移動する。
---日本語 (。！？…) と英語 (. ! ? + 空白・行末) の文末を判定する
---(_core.sentence)。文末が見つからなければカーソルは動かない。
---カーソルが文末の上にある場合は、それより後ろの文末を探す。
---@param count? number
---@return boolean 移動したか
function M.next_sentence_end(count)
  return require("bunsetsu._commands.sentence").next_end(count or 1)
end

---前の文末へ移動する。
---@param count? number
---@return boolean 移動したか
function M.prev_sentence_end(count)
  return require("bunsetsu._commands.sentence").prev_end(count or 1)
end

---デバッグ用: 設定内容を表示する。
function M.show_config()
  print(vim.inspect(configuration.DATA))
end

---指定語の辞書形(原形)を UniDic から引く。
---
---Vaporetto で分割した語の表層形を渡すと、原形・読み・品詞を返す。
---例: "走っ" -> { lemma = "走る", reading = "ハシル", pos = "動詞" }
---辞書に無い語や設定が空の場合は nil を返す。
---
---@param surface string 表層形
---@return { lemma: string, reading: string, pos: string } | nil
function M.lemma(surface)
  local path = configuration.DATA.lemma.dict_path
  if path == "" then
    return nil
  end
  return lemma.lookup(surface, path)
end

---カーソル下の語の辞書形・読み・品詞を返す。
---
---カーソル位置の文字が ASCII なら Vim の cword を使う。
---日本語なら Vibrato で分割し、カーソル位置を含む語の原形を引く。
---Vibrato は原形・読み・品詞を直接出力するため、辞書引きは不要。
---返り値: { surface, lemma, reading, pos } | nil
---
---@return { surface: string, lemma: string, reading: string, pos: string } | nil
function M.lemma_under_cursor()
  local line = vim.fn.getline(".")
  if line == "" then
    return nil
  end

  local cursor = vim.fn.col(".")

  -- 行に日本語 (かな・漢字) が無ければ ASCII とみなして cword を使う
  if not lang.has_japanese(line) then
    local cword = vim.fn.expand("<cword>")
    if cword == "" then
      return nil
    end
    return { surface = cword, lemma = cword, reading = "", pos = "" }
  end

  -- 日本語: Vibrato で分割してカーソル位置を含む語を特定
  local vibrato = require("bunsetsu._commands.vibrato")
  local segment = require("bunsetsu._core.segment")
  local words, infos = vibrato.tokenize_detailed(line)
  local positions = segment.word_positions(line, words)
  for i, word in ipairs(words) do
    local start_col = positions[i]
    local end_col = start_col + #word - 1
    if cursor >= start_col and cursor <= end_col then
      local info = infos[i] or {}
      return {
        surface = word,
        lemma = (info.lemma ~= "" and info.lemma) or word,
        reading = info.reading or "",
        pos = info.pos or "",
      }
    end
  end
  return nil
end

return M
