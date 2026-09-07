---全文モード: バッファ全体の segment を事前計算する。
--
-- パフォーマンス方針:
--   * 分割は Vibrato (常駐プロセス) で行う。モデルロードはプロセス起動時に1回。
--   * Vibrato 辞書が未設定のときは同梱の TinySegmenter モデルで分割する。
--   * 分節化は「行単位」でキャッシュする。行内容が変わらなければ再計算しない。
--   * フラットな FullSegment[] は `full()` 呼び出し時にキャッシュから組み立てる。
--   * 編集時は `invalidate(lnum)` で該当行のキャッシュだけを破棄する。

local M = {}

---@class FullSegment
---@field lnum number 行番号(1始まり)
---@field col number 開始列(バイト位置、1始まり)
---@field colend number 終了列(バイト位置、1始まり)
---@field idx number 行内のsegmentインデックス(1始まり)
---@field text string segment文字列

---行ごとの分節キャッシュ。key: 行番号 => { line, segcols }
---@type table<string, table<number, { line: string, segcols: SegmentCol[] }>>
local linecache = {}

---モデルごとのフラット配列キャッシュ
---@type table<string, FullSegment[]>
local fullcache = {}

---モデル名のリスト (キャッシュ用に使い回す)
---@type table<string, true>
local known_models = {}

---Vibrato で行を文節分割して SegmentCol[] を返す。
---助詞・助動詞の結合と splitpat の強制区切りは _core.segment に一任する。
---@param line string
---@return SegmentCol[]
local function vibrato_segments(line)
  local vibrato = require("bunsetsu._commands.vibrato")
  local segment = require("bunsetsu._core.segment")
  local words, infos = vibrato.tokenize_detailed(line)
  local positions = segment.word_positions(line, words)
  return segment.words_to_segments(words, positions, infos)
end

---外部トークナイザ (Vibrato) を使うかどうか。辞書未設定なら TinySegmenter。
---@return boolean
function M.use_vibrato()
  local config = require("bunsetsu._core.configuration")
  local dict = config.DATA.vibrato and config.DATA.vibrato.dict or ""
  return dict ~= ""
end

---行を文節分割して SegmentCol[] を返す (バックエンドは設定に従う)。
---@param model_name string
---@param line string
---@return SegmentCol[]
local function line_segments(model_name, line)
  if M.use_vibrato() then
    return vibrato_segments(line)
  end
  local seg = require("bunsetsu._core.segment")
  return seg.split_line(model_name, line)
end

---指定行の分節結果をキャッシュから返す。行内容が変わっていれば再計算する。
---@param model_name string
---@param lnum number
---@param line string
---@return SegmentCol[]
local function get_line(model_name, lnum, line)
  local per_line = linecache[model_name]
  if per_line and per_line[lnum] and per_line[lnum].line == line then
    return per_line[lnum].segcols
  end
  local segcols = line_segments(model_name, line)
  linecache[model_name] = linecache[model_name] or {}
  linecache[model_name][lnum] = { line = line, segcols = segcols }
  return segcols
end

---バッファ全体を分節化して segment 位置一覧を返す (キャッシュ使用)。
---@param model_name string
---@return FullSegment[]
function M.full(model_name)
  local cached = fullcache[model_name]
  if cached then
    return cached
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local result = {}
  for lnum, line in ipairs(lines) do
    local segcols = get_line(model_name, lnum, line)
    for idx, sc in ipairs(segcols) do
      result[#result + 1] = {
        lnum = lnum,
        col = sc.col,
        colend = sc.colend,
        idx = idx,
        text = sc.segment,
      }
    end
  end
  fullcache[model_name] = result
  known_models[model_name] = true
  return result
end

---バッファ全体をバックグラウンドで分割してキャッシュする。
---ファイルを開いたときに呼ぶことで、spider 移動時の待ち時間を解消する。
---同期的に実行するとブロックするため、vim.schedule で段階的に処理する。
---@param model_name string
function M.preload(model_name)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then
    return
  end

  -- TinySegmenter バックエンドは常駐プロセスが不要なため、
  -- 初回 full() 呼び出し時の分割で足りる (プリロード不要)。
  if not M.use_vibrato() then
    return
  end

  -- 日本語を含む行だけを対象にする (ASCII のみは Vibrato 不要)
  local jp_lines = {} ---@type {lnum: number, line: string}[]
  for lnum, line in ipairs(lines) do
    if line:match("[ぁ-んァ-ヶー一-龠]") then
      jp_lines[#jp_lines + 1] = { lnum = lnum, line = line }
    end
  end
  if #jp_lines == 0 then
    return
  end

  -- 非同期で全行を分割して linecache に保存する。
  local segment = require("bunsetsu._core.segment")
  local vibrato = require("bunsetsu._commands.vibrato")
  vibrato.tokenize_async(jp_lines, function(results)
    -- results: { lnum = 行番号, words = string[], positions = number[] }[]
    linecache[model_name] = linecache[model_name] or {}
    for _, r in ipairs(results) do
      local segcols = segment.words_to_segments(r.words, r.positions, r.infos)
      linecache[model_name][r.lnum] = { line = r.line, segcols = segcols }
    end
    known_models[model_name] = true
    fullcache[model_name] = nil -- フラット配列は後で必要時に再構築
  end)
end

---現在カーソル位置以降の最初の segment を返す。
---@param model_name string
---@return FullSegment|nil
function M.next(model_name)
  local cursor = vim.api.nvim_win_get_cursor(0) -- { lnum, col }  colは0始まり
  local cur_lnum, cur_col = cursor[1], cursor[2] + 1
  for _, fs in ipairs(M.full(model_name)) do
    if fs.lnum > cur_lnum or (fs.lnum == cur_lnum and fs.col > cur_col) then
      return fs
    end
  end
  return nil
end

---現在カーソル位置以前の最後の segment を返す。
---カーソルが segment 内部にある場合はその segment を返す。
---@param model_name string
---@return FullSegment|nil
function M.prev(model_name)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cur_lnum, cur_col = cursor[1], cursor[2] + 1
  local prev = nil
  for _, fs in ipairs(M.full(model_name)) do
    if fs.lnum < cur_lnum or (fs.lnum == cur_lnum and fs.colend < cur_col) then
      prev = fs
    elseif fs.lnum == cur_lnum and fs.col <= cur_col and fs.colend >= cur_col then
      -- カーソルがこの segment 内にある
      return fs
    end
  end
  return prev
end

---指定範囲の segment を返す。
---@param model_name string
---@param start_lnum number
---@param end_lnum number
---@return FullSegment[]
function M.range(model_name, start_lnum, end_lnum)
  local result = {}
  for _, fs in ipairs(M.full(model_name)) do
    if fs.lnum >= start_lnum and fs.lnum <= end_lnum then
      result[#result + 1] = fs
    end
  end
  return result
end

---キャッシュを破棄する。
---lnum を指定すると該当行のみ、省略すると全行破棄する。
---@param lnum? number
function M.invalidate(lnum)
  if lnum then
    for model_name in pairs(known_models) do
      if linecache[model_name] then
        linecache[model_name][lnum] = nil
      end
      fullcache[model_name] = nil
    end
    return
  end
  linecache = {}
  fullcache = {}
end

---指定行を再分割してキャッシュを更新する。
---変更があった行だけを再処理する (全文再分割しない)。
---@param model_name string
---@param lnum number 変更された行番号 (1始まり)
function M.refresh_line(model_name, lnum)
  if lnum == nil or lnum < 1 then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
  if line == nil then
    return
  end

  -- TinySegmenter バックエンド: 純 Lua の分割なので同期で処理する
  if not M.use_vibrato() then
    local seg = require("bunsetsu._core.segment")
    local segcols = seg.split_line(model_name, line)
    linecache[model_name] = linecache[model_name] or {}
    linecache[model_name][lnum] = { line = line, segcols = segcols }
    fullcache[model_name] = nil
    known_models[model_name] = true
    return
  end

  -- 日本語を含まない行は空セグメントとしてキャッシュ
  if not line:match("[ぁ-んァ-ヶー一-龠]") then
    linecache[model_name] = linecache[model_name] or {}
    linecache[model_name][lnum] = { line = line, segcols = {} }
    fullcache[model_name] = nil
    known_models[model_name] = true
    return
  end

  -- 非同期で1行だけ再分割
  local segment = require("bunsetsu._core.segment")
  local vibrato = require("bunsetsu._commands.vibrato")
  vibrato.tokenize_async({ { lnum = lnum, line = line } }, function(results)
    linecache[model_name] = linecache[model_name] or {}
    local segcols = {}
    if #results > 0 then
      local r = results[1]
      segcols = segment.words_to_segments(r.words, r.positions, r.infos)
    end
    linecache[model_name][lnum] = { line = line, segcols = segcols }
    fullcache[model_name] = nil -- フラット配列は必要時に再構築
    known_models[model_name] = true
  end)
end

return M
