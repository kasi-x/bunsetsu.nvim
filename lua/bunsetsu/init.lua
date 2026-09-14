--- All function(s) that can be called externally by other Lua modules.
---
--- If a function's signature here changes in some incompatible way, this
--- package must get a new **major** version.
---
--- bunsetsu.nvim は nvim-spider と flash.nvim の日本語文節拡張を提供する。

local configuration = require("bunsetsu._core.configuration")
local full = require("bunsetsu._commands.full")
local lang = require("bunsetsu._core.lang")
local lemma = require("bunsetsu._core.lemma")
local lifecycle = require("bunsetsu._core.lifecycle")

local M = {}

configuration.initialize_data_if_needed()

--- Setup `bunsetsu.nvim`.
---
---@param opts? Bunsetsu.Config All extra customizations for this plugin.
function M.setup(opts)
  lifecycle.setup(opts)
end

---全文モードの segment 一覧を返す (flash matcher の基盤)。
---@return FullSegment[]
function M.full_segments()
  return full.full(configuration.current_model())
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
    if configuration.use_vibrato() then
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
---日本語ならトークナイザで分割し、カーソル位置を含む語を返す。
---Vibrato 設定時は品詞・原形・読みつき。未設定なら同梱 TinySegmenter に
---フォールバックする (lemma = surface、pos / reading は空)。
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

  -- 日本語: トークナイザで分割してカーソル位置を含む語を特定
  local segment = require("bunsetsu._core.segment")
  local tokens = {} ---@type { surface: string, start: number, pos: string, lemma: string, reading: string }[]

  if configuration.use_vibrato() then
    local vibrato = require("bunsetsu._commands.vibrato")
    local words, infos = vibrato.tokenize_detailed(line)
    local positions = segment.word_positions(line, words)
    for i, word in ipairs(words) do
      local info = infos[i] or {}
      tokens[#tokens + 1] = {
        surface = word,
        start = positions[i],
        pos = info.pos or "",
        lemma = (info.lemma ~= "" and info.lemma) or word,
        reading = info.reading or "",
      }
    end
  else
    -- TinySegmenter フォールバック: 品詞情報は取れない (surface のみ)
    for _, sc in ipairs(segment.segment_col_line(configuration.DATA.model, line)) do
      tokens[#tokens + 1] = {
        surface = sc.segment,
        start = sc.col,
        pos = "",
        lemma = sc.segment,
        reading = "",
      }
    end
  end

  for _, t in ipairs(tokens) do
    if cursor >= t.start and cursor <= t.start + #t.surface - 1 then
      return { surface = t.surface, lemma = t.lemma, reading = t.reading, pos = t.pos }
    end
  end
  return nil
end

return M
