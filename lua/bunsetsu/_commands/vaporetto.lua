---Vaporetto バックエンド。単語分割を実行して文節境界を提供する。
--
-- Vaporetto (https://github.com/daac-tools/vaporetto) の predict CLI を使い、
-- 日本語を単語分割する。
--
-- プロセス管理 (sync / async の 2 接続) は共通エンジン
-- (_core.tokenizer_engine) に一任する。

local config = require("bunsetsu._core.configuration")
local engine_mod = require("bunsetsu._core.tokenizer_engine")
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

---常駐プロセスの共通エンジン (sync + async)。
local engine = engine_mod.new({
  build_cmd = function()
    local vaporetto = config.DATA.vaporetto
    local model = vaporetto.model
    if not model or model == "" then
      return nil
    end
    return { vaporetto.cmd or "predict", "--model", model, "--predict-tags" }
  end,
  classify = function(line)
    if line:find("Start tokenization") then
      return "ready"
    elseif line:find("Loading model file") or line:find("^Elapsed:") then
      return "skip"
    elseif line ~= "" and line:find("/") then
      -- pty のエコーバック (分割結果以外) は / を含まないので除外
      return "result"
    end
    return "skip"
  end,
  block_mode = "line",
})

-- ---------------------------------------------------------------------------
-- 出力パース
-- ---------------------------------------------------------------------------

---predict-tags 出力 "単語/品詞/読み ..." を単語と位置に分解する。
---@param out string predict の出力 (1行)
---@param line string 元の行 (位置計算用)
---@return string[] words
---@return number[] positions
local function parse_tokens(out, line)
  local words = {}
  local positions = {}
  local search_from = 1
  for token in out:gmatch("%S+") do
    local parts = vim.split(token, "/", { plain = true })
    local tok = parts[1] or ""
    if tok == "\\" then
      search_from = search_from + 1
    elseif tok ~= "" then
      local found = vim.fn.stridx(line, tok, search_from - 1) + 1
      if found <= 0 then
        found = search_from
      end
      words[#words + 1] = tok
      positions[#positions + 1] = found
      search_from = found + #tok
    end
  end
  return words, positions
end

---同期 predict を実行して出力行を返す。
---@param line string 入力行
---@return string output predict の出力 (1行)
local function sync_predict(line)
  local block = engine:sync_request(line)
  return block and block[1] or ""
end

-- ---------------------------------------------------------------------------
-- 同期プロセス
-- ---------------------------------------------------------------------------

---Vaporetto で行を単語分割する。失敗時は空配列。
---日本語を含まない行は分割せず空配列を返す。
---@param line string
---@return string[] words 単語の文字列
---@return number[] positions 各単語の開始位置 (1-based byte)
function M.tokenize(line)
  if not has_japanese(line) then
    return {}, {}
  end
  local out = sync_predict(line)
  if out == "" then
    return {}, {}
  end
  return parse_tokens(out, line)
end

---Vaporetto で行を単語分割し、各語の POS タグを返す。
---@param line string
---@return string[] words 単語
---@return string[] tags POS タグ (例: "名詞-普通名詞-サ変可能")
function M.tokenize_with_tags(line)
  if not has_japanese(line) then
    return {}, {}
  end
  local out = sync_predict(line)
  if out == "" then
    return {}, {}
  end
  local words = {}
  local tags = {}
  for token in out:gmatch("%S+") do
    local parts = vim.split(token, "/", { plain = true })
    if #parts >= 1 and parts[1] ~= "" and parts[1] ~= "\\" then
      words[#words + 1] = parts[1]
      tags[#tags + 1] = parts[2] or ""
    end
  end
  return words, tags
end

-- ---------------------------------------------------------------------------
-- 非同期プロセス
-- ---------------------------------------------------------------------------

---複数行を非同期で分割する (全文プリロード・行再分割用)。
---vim.wait を使わないため、編集処理やタイマーと競合しない。
---
---@param lines {lnum: number, line: string}[] 行番号と行の配列
---@param on_done fun(results: {lnum: number, line: string, words: string[], positions: number[]}[])
function M.tokenize_async(lines, on_done)
  if #lines == 0 then
    on_done({})
    return
  end
  if not engine:ensure_job("async") then
    -- async プロセスが使えない場合は同期にフォールバック
    local results = {}
    for _, item in ipairs(lines) do
      local words, positions = M.tokenize(item.line)
      results[#results + 1] = {
        lnum = item.lnum,
        line = item.line,
        words = words,
        positions = positions,
      }
    end
    on_done(results)
    return
  end

  engine:tokenize_async(lines, function(results)
    local out = {}
    for _, r in ipairs(results) do
      local words, positions = parse_tokens(table.concat(r.block, "\n"), r.item.line)
      out[#out + 1] = {
        lnum = r.item.lnum,
        line = r.item.line,
        words = words,
        positions = positions,
      }
    end
    on_done(out)
  end)
end

-- ---------------------------------------------------------------------------
-- spider 用パターン
-- ---------------------------------------------------------------------------

---現在行の単語分割結果をキャッシュから返す。
---@param line string
---@return string[] 単語の文字列
---@return number[] 各単語の開始位置 (1-based byte)
local linecache = nil

local function get_words(line)
  if linecache and linecache.line == line then
    return linecache.words, linecache.positions
  end
  local words, positions = M.tokenize(line)
  linecache = { line = line, words = words, positions = positions }
  return words, positions
end

---Vaporetto の単語分割結果を、spider の customPatterns に渡す境界関数に変換する。
---@param mode "word"|"bunsetsu" 境界の粒度
---@return fun(line: string, searchOffset: number, key: string, backwards: boolean): number|false
function M.pattern(mode)
  mode = mode or "word"
  return function(line, searchOffset, key, backwards)
    local words, positions = get_words(line)
    if #words == 0 then
      return false
    end

    -- 文節境界 (開始位置と終端位置)。位置はすべてバイト座標
    local boundaries = {}
    local boundaryEnds = {}
    for i in ipairs(words) do
      if mode == "bunsetsu" and i > 1 and is_particle(words[i]) then
        -- 助詞を前の語に結合する: 終端を伸ばす
        if #boundaries > 0 then
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

    -- key に応じて位置を調整 (終端位置 e/ge は boundaryEnds[i])
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

---助詞・助動詞かどうかの簡易判定。
---@param word string
---@return boolean
function M.is_particle(word)
  local particles = {
    "は",
    "を",
    "に",
    "へ",
    "が",
    "と",
    "も",
    "で",
    "や",
    "か",
    "の",
    "ね",
    "よ",
    "ぞ",
    "な",
    "わ",
    "ず",
    "ば",
  }
  for _, p in ipairs(particles) do
    if word == p then
      return true
    end
  end
  local auxiliaries = { "です", "ます", "た", "ない", "いる", "ある" }
  for _, a in ipairs(auxiliaries) do
    if word == a then
      return true
    end
  end
  return false
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

return M
