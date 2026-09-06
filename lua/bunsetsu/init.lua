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
local lemma = require("bunsetsu._core.lemma")

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
      -- 変更行のみ非同期で再分割してキャッシュ更新
      vim.schedule(function()
        full.refresh_line(model_name(), lnum)
      end)
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

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
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
      -- 全行キャッシュ破棄 + 全文をバックグラウンドで分割
      on_change()
      -- 品詞ハイライト (オプション)
      apply_highlight(vim.api.nvim_get_current_buf())
      -- 行数・undo 位置の追跡をリセット
      local buf = vim.api.nvim_get_current_buf()
      buf_line_counts[buf] = vim.api.nvim_buf_line_count(buf)
      buf_undo_seqs[buf] = vim.fn.undotree().seq_cur
    end,
  })

  -- TextChanged でも変更行のハイライトを更新
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      if hl_enabled then
        local buf = vim.api.nvim_get_current_buf()
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

---指定行を文節区切りで分かち書きして置換する (:BunsetsuSplit 相当)。
---@param line1 number
---@param line2 number
function M.split_lines(line1, line2)
  local sep = configuration.DATA.splitsep
  local vibrato = require("bunsetsu._commands.vibrato")
  local use_vibrato = configuration.DATA.vibrato and configuration.DATA.vibrato.dict ~= ""
  for lnum = line1, line2 do
    local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
    local segs = {}
    if use_vibrato then
      local words, infos = vibrato.tokenize_detailed(line)
      -- 助詞を前の語に結合して文節を作る
      local buf = {}
      for i, w in ipairs(words) do
        local pos = infos[i] and infos[i].pos or ""
        if i > 1 and vibrato.is_particle(pos) and #segs > 0 then
          -- 助詞は前の文節に結合
          buf[#buf + 1] = w
        else
          if #buf > 0 then
            segs[#segs + 1] = table.concat(buf)
          end
          buf = { w }
        end
      end
      if #buf > 0 then
        segs[#segs + 1] = table.concat(buf)
      end
    else
      -- TinySegmenter バックエンド
      local segment = require("bunsetsu._core.segment")
      for _, sc in ipairs(segment.split_line(configuration.DATA.model, line)) do
        segs[#segs + 1] = sc.segment
      end
    end
    vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { table.concat(segs, sep) })
  end
  full.invalidate()
end

---利用可能なバックエンドを返す。
---Vibrato 辞書が設定されていれば "vibrato" を含む。
---@return string[]
function M.models()
  local ret = {}
  local dict = configuration.DATA.vibrato.dict
  if dict and dict ~= "" then
    ret[#ret + 1] = "vibrato"
  end
  return ret
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
  if not line:match("[ぁ-んァ-ヶー一-龠]") then
    local cword = vim.fn.expand("<cword>")
    if cword == "" then
      return nil
    end
    return { surface = cword, lemma = cword, reading = "", pos = "" }
  end

  -- 日本語: Vibrato で分割してカーソル位置を含む語を特定
  local vibrato = require("bunsetsu._commands.vibrato")
  local words, infos = vibrato.tokenize_detailed(line)
  local search_from = 1
  for i, word in ipairs(words) do
    local found = vim.fn.stridx(line, word, search_from - 1) + 1
    if found <= 0 then
      found = search_from
    end
    local start_col = found
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
    search_from = found + #word
  end
  return nil
end

return M
