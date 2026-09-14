---Vibrato バックエンド。日本語の形態素解析 (単語分割 + 品詞 + 原形 + 読み)。
--
-- Vibrato (https://github.com/daac-tools/vibrato) の tokenize CLI を使い、
-- MeCab 形式の辞書 (ipadic 等) で日本語を単語分割する。
--
-- 出力形式 (MeCab 形式):
--   表層形\t品詞,...,原形,読み,発音
--
-- 原形 (列7) と読み (列8) を出力に含むため、辞書引きは不要。
--
-- プロセス管理 (sync / async の 2 接続) は共通エンジン
-- (_core.tokenizer_engine) に一任する。

local config = require("bunsetsu._core.configuration")
local engine_mod = require("bunsetsu._core.tokenizer_engine")
local segment = require("bunsetsu._core.segment")
local lang = require("bunsetsu._core.lang")

local M = {}

-- M.is_particle への前方参照 (pattern 内で使用)
local is_particle

---日本語を含む行かどうか。
---@param line string
---@return boolean
local function has_japanese(line)
  return lang.has_japanese(line)
end

---MeCab 形式の行 "表層形\t品詞,...,原形,読み,発音" を分解する。
---@param line string
---@return table { surface, pos, lemma, reading }
local function parse_line(line)
  local surface, features = line:match("^([^\t]+)\t(.+)$")
  if not surface then
    return nil
  end
  local cols = vim.split(features, ",", { plain = true })
  -- 列7=原形, 列8=読み (ipadic 形式)。無ければ表層形を使う。
  local lemma = cols[7] or surface
  local reading = cols[8] or ""
  return {
    surface = surface,
    pos = cols[1] or "",
    lemma = lemma,
    reading = reading,
  }
end

---常駐プロセスの共通エンジン (sync + async)。
local engine = engine_mod.new({
  build_cmd = function()
    local v = config.DATA.vibrato
    if not v.dict or v.dict == "" then
      return nil
    end
    return { v.cmd or "vibrato", "-i", v.dict }
  end,
  classify = function(line)
    if line:find("Ready to tokenize") then
      return "ready"
    elseif line:find("Loading the dictionary") then
      return "skip"
    elseif line == "EOS" then
      return "eos"
    elseif line ~= "" and line:find("\t") then
      -- pty のエコーバック (分割結果以外) は \t を含まないので除外
      return "result"
    end
    return "skip"
  end,
  block_mode = "eos",
})

---ブロック (MeCab 形式の出力行の配列) をトークンに分解する。
---@param block string[]
---@return table[] tokens (parse_line の結果)
local function parse_block(block)
  local tokens = {}
  for _, out in ipairs(block) do
    local t = parse_line(out)
    if t then
      tokens[#tokens + 1] = t
    end
  end
  return tokens
end

---トークン列から、元の行内の各語の開始位置を求める。
---@param line string
---@param tokens table[]
---@return string[] words
---@return number[] positions
---@return table[] infos
local function to_words_positions_infos(line, tokens)
  local words, infos = {}, {}
  for _, t in ipairs(tokens) do
    words[#words + 1] = t.surface
    infos[#infos + 1] = { pos = t.pos, lemma = t.lemma, reading = t.reading }
  end
  local positions = segment.word_positions(line, words)
  return words, positions, infos
end

-- ---------------------------------------------------------------------------
-- 同期プロセス
-- ---------------------------------------------------------------------------

---同期 tokenize を実行して、行ごとのパース結果を返す。
---@param line string 入力行
---@return table[] tokens (parse_line の結果)
local function sync_tokenize(line)
  local block = engine:sync_request(line)
  if not block then
    return {}
  end
  return parse_block(block)
end

---Vibrato で行を単語分割する。
---@param line string
---@return string[] words 表層形
---@return number[] positions 各単語の開始位置 (1-based byte)
function M.tokenize(line)
  if not has_japanese(line) then
    return {}, {}
  end
  local words, positions, _ = M.tokenize_detailed(line)
  return words, positions
end

---Vibrato で行を単語分割し、各語の詳細情報 (品詞・原形・読み) を返す。
---@param line string
---@return string[] words
---@return table[] infos { pos, lemma, reading }
function M.tokenize_detailed(line)
  if not has_japanese(line) then
    return {}, {}
  end
  local words, positions, infos = to_words_positions_infos(line, sync_tokenize(line))
  return words, infos, positions
end

-- ---------------------------------------------------------------------------
-- 非同期プロセス
-- ---------------------------------------------------------------------------

---複数行を非同期で分割する (全文プリロード・行再分割用)。
---@param lines {lnum: number, line: string}[] 行番号と行の配列
---@param on_done fun(results: {lnum: number, line: string, words: string[], positions: number[], infos: table[]}[])
function M.tokenize_async(lines, on_done)
  if #lines == 0 then
    on_done({})
    return
  end
  if not engine:ensure_job("async") then
    -- async プロセスが使えない場合は同期にフォールバック
    local results = {}
    for _, item in ipairs(lines) do
      local words, positions, infos = to_words_positions_infos(item.line, sync_tokenize(item.line))
      results[#results + 1] = {
        lnum = item.lnum,
        line = item.line,
        words = words,
        positions = positions,
        infos = infos,
      }
    end
    on_done(results)
    return
  end

  engine:tokenize_async(lines, function(results)
    local out = {}
    for _, r in ipairs(results) do
      local words, positions, infos = to_words_positions_infos(r.item.line, parse_block(r.block))
      out[#out + 1] = {
        lnum = r.item.lnum,
        line = r.item.line,
        words = words,
        positions = positions,
        infos = infos,
      }
    end
    on_done(out)
  end)
end

-- ---------------------------------------------------------------------------
-- spider 用パターン
-- ---------------------------------------------------------------------------

---現在行の単語分割結果 (品詞込み) をキャッシュから返す。
---@param line string
---@return string[] 単語の文字列
---@return number[] 各単語の開始位置 (1-based byte)
---@return table[] 各単語の詳細 { pos, lemma, reading }
local linecache = nil

local function get_words(line)
  if linecache and linecache.line == line then
    return linecache.words, linecache.positions, linecache.infos
  end
  local words, infos, positions = M.tokenize_detailed(line)
  linecache = { line = line, words = words, positions = positions, infos = infos }
  return words, positions, infos
end

---Vibrato の分割結果を、spider の customPatterns に渡す境界関数に変換する。
---@param mode "word"|"bunsetsu" 境界の粒度
---@return fun(line: string, searchOffset: number, key: string, backwards: boolean): number|false
function M.pattern(mode)
  mode = mode or "word"
  return function(line, searchOffset, key, backwards)
    local words, positions, infos = get_words(line)
    if #words == 0 then
      return false
    end

    -- 文節境界 (開始位置と終端位置)。位置はすべてバイト座標
    local boundaries = {}
    local boundaryEnds = {}
    for i in ipairs(words) do
      if mode == "bunsetsu" and i > 1 and is_particle(infos[i].pos) then
        if #boundaries > 0 then
          -- 助詞を前の文節に結合: 終端を伸ばす
          boundaryEnds[#boundaryEnds] = positions[i] + #words[i] - 1
        end
      else
        boundaries[#boundaries + 1] = positions[i]
        boundaryEnds[#boundaryEnds + 1] = positions[i] + #words[i] - 1
      end
    end

    if #boundaries == 0 then
      return false
    end

    local target = function(i)
      if key == "e" or key == "ge" then
        return boundaryEnds[i]
      end
      return boundaries[i]
    end

    -- 移動方向にある最も近い境界を返す (元の行のバイト座標)
    local best
    for i in ipairs(boundaries) do
      local t = target(i)
      if backwards then
        if t < searchOffset and (not best or t > best) then
          best = t
        end
      elseif t > searchOffset and (not best or t < best) then
        best = t
      end
    end
    return best or false
  end
end

---@param pos string
---@return boolean
function M.is_particle(pos)
  if not pos or pos == "" then
    return false
  end
  -- 品詞大分類 (「助詞,係助詞」→「助詞」)
  local big = vim.split(pos, ",", { plain = true })[1]
  return big == "助詞" or big == "助動詞"
end

is_particle = M.is_particle

-- ---------------------------------------------------------------------------
-- キャッシュ・プロセス管理
-- ---------------------------------------------------------------------------

---キャッシュをクリアする。
function M.clear_cache()
  linecache = nil
end

---常駐プロセスを終了する。
function M.stop()
  engine:stop()
  linecache = nil
end

---同期プロセスが起動しているか。
---@return boolean
function M.is_running()
  return engine:is_running()
end

return M
