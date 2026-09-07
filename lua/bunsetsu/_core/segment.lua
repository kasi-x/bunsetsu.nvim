---行を文節(segment)に分割する。bunsetsu.vim の bunsetsu#SegmentCol の Lua 移植。
--
-- パフォーマンス方針: flash.nvim と同様に、ホットパスでは Vimscript 関数
-- (vim.fn.*) を一切呼ばず、純 Lua の文字列操作と utf8 反復のみで処理する。
--
-- 分割は「スペース区切りの塊」→「モデルによる文節区切り」→「splitpat による
-- 強制区切り」の順で行い、各 segment の開始列/終了列(バイト位置)を返す。
--
-- 返り値の形式 (bunsetsu.vim と互換):
--   [ { segment = '文節', col = 1, colend = 3 }, ... ]
-- col / colend はバイト位置(1始まり)。

local models = require("bunsetsu._core.models")
local config = require("bunsetsu._core.configuration")
local utf8 = require("bunsetsu._core.utf8")

local M = {}

---@type table<string, { line: string, segcols: SegmentCol[] }>
local cache = {}

---@class SegmentCol
---@field segment string
---@field col number
---@field colend number

-- ---------------------------------------------------------------------------
-- splitpat (強制区切り) の評価
-- ---------------------------------------------------------------------------

---splitpat の文字列から「強制区切り文字」の集合を作る。
---シンプルな文字クラス '[...]' のみを解釈する (多バイト文字も可)。
---それ以外の形式 (Vim 正規表現など) は解釈せず nil を返す。
---@param splitpat string
---@return table<string, boolean>|nil
local function compile_punct_set(splitpat)
  if splitpat:sub(1, 1) ~= "[" or splitpat:sub(-1) ~= "]" then
    return nil
  end
  local body = splitpat:sub(2, -2)
  if body:find("%[") or body:find("%]") then
    return nil
  end
  local set = {}
  local i = 1
  while i <= #body do
    local b = body:byte(i)
    if b == 0x25 then
      -- '%x' 形式は解釈せず諦める (安全側にフォールバックさせる)
      return nil
    end
    local len = b < 0x80 and 1 or (b < 0xE0 and 2 or (b < 0xF0 and 3 or 4))
    set[body:sub(i, i + len - 1)] = true
    i = i + len
  end
  return set
end

---既定の強制区切り文字 ('[?!、。]' 相当)。
local DEFAULT_PUNCT_SET = { ["?"] = true, ["!"] = true, ["、"] = true, ["。"] = true }

---@type table<string, table<string, boolean>|nil>
local punct_set_cache = {}

---splitpat に対応する区切り文字集合を返す (キャッシュ付き)。
---解釈できないパターンは既定値 '[?!、。]' にフォールバックする。
---@param splitpat string
---@return table<string, boolean>
local function get_punct_set(splitpat)
  if splitpat == "" then
    return {}
  end
  if punct_set_cache[splitpat] == nil then
    punct_set_cache[splitpat] = compile_punct_set(splitpat) or DEFAULT_PUNCT_SET
  end
  return punct_set_cache[splitpat]
end

---空白文字(U+0020, タブ等, U+3000)かどうか
---@param ch string
---@return boolean
local function is_space_char(ch)
  if #ch == 1 then
    local b = ch:byte()
    return b == 0x20 or (b >= 0x09 and b <= 0x0D)
  end
  return ch == "　"
end

---スペース区切りで分割する。スペースは前の segment の末尾に付ける。
---'a  b　c' => { 'a  ', 'b　', 'c' } (vim.fn.split と同一挙動)
---@param s string
---@return string[]
local function split_spaces(s)
  local result = {}
  local buf = {}
  local prev_space = false
  for _, ch in utf8.codes(s) do
    if is_space_char(ch) then
      buf[#buf + 1] = ch
      prev_space = true
    else
      if prev_space and #buf > 0 then
        result[#result + 1] = table.concat(buf)
        buf = {}
      end
      buf[#buf + 1] = ch
      prev_space = false
    end
  end
  if #buf > 0 then
    result[#result + 1] = table.concat(buf)
  end
  return result
end

---文字列から空白文字を除去する。
---@param s string
---@return string
local function strip_spaces(s)
  local out = {}
  for _, ch in utf8.codes(s) do
    if not is_space_char(ch) then
      out[#out + 1] = ch
    end
  end
  return table.concat(out)
end

---非ASCII(マルチバイト文字)を含むか判定する。
---@param s string
---@return boolean
local function has_multibyte(s)
  for i = 1, #s do
    if s:byte(i) >= 0x80 then
      return true
    end
  end
  return false
end

---splitpat (強制区切り文字) の直後で分割する。句読点は前の塊に残る。
---'a、b。c' => { 'a、', 'b。', 'c' }
---@param s string
---@param punct_set table<string, boolean> 強制区切り文字の集合
---@return string[]
local function split_by_splitpat(s, punct_set)
  local result = {}
  local buf = {}
  local in_punct_run = false
  local prev_non_space = false
  for _, ch in utf8.codes(s) do
    local is_punct = punct_set[ch] == true
    local is_sp = is_space_char(ch)
    if is_punct then
      if prev_non_space then
        buf[#buf + 1] = ch
        in_punct_run = true
      else
        buf[#buf + 1] = ch
        in_punct_run = false
      end
    else
      if in_punct_run then
        result[#result + 1] = table.concat(buf)
        buf = {}
        in_punct_run = false
      end
      buf[#buf + 1] = ch
    end
    prev_non_space = not is_sp
  end
  if #buf > 0 then
    result[#result + 1] = table.concat(buf)
  end
  return result
end

---モデル名から分割関数を取得する。未知の場合は入力文字列をそのまま1文節として返す。
---@param model_name string
---@return fun(input: string): string[]
local function get_segment_fn(model_name)
  local fn = models.get(model_name)
  if fn then
    return fn
  end
  return function(input)
    return { input }
  end
end

---モデル固有の splitpat を取得する。無ければグローバル設定を使う。
---@param model_name string
---@return string
local function get_splitpat(model_name)
  local model_splitpat = models.splitpat(model_name)
  if model_splitpat ~= nil then
    return model_splitpat
  end
  return config.DATA.splitpat
end

---行を segment 列情報の配列に変換する(キャッシュ付き)。
---@param model_name string
---@param line string
---@return SegmentCol[]
function M.segment_col_line(model_name, line)
  local cached = cache[model_name]
  if cached and cached.line == line then
    return cached.segcols
  end
  local segcols = M.split_line(model_name, line)
  cache[model_name] = { line = line, segcols = segcols }
  return segcols
end

---現在バッファの指定行を segment 列情報の配列に変換する。
---@param model_name string
---@param lnum number
---@return SegmentCol[]
function M.segment_col(model_name, lnum)
  local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
  return M.segment_col_line(model_name, line)
end

---スペース区切り + モデル分節 + splitpat のフル分割を行う。
---@param model_name string
---@param line string
---@return SegmentCol[]
function M.split_line(model_name, line)
  -- スペース区切りの segment に分割。スペースは後続 segment に含まれる。
  local spsegs = split_spaces(line)
  if #spsegs == 0 then
    return {}
  end

  local segment_fn = get_segment_fn(model_name)
  local splitpat = get_splitpat(model_name)
  local punct_set = get_punct_set(splitpat)

  -- spsegcols: { segment = string[], col = number }
  local spsegcols = {}
  local col = 1
  for _, spseg in ipairs(spsegs) do
    local seglen = #spseg
    local nextcol = col + seglen
    local spseg_nospace = strip_spaces(spseg)
    if spseg_nospace ~= "" then
      local segs
      if has_multibyte(spseg_nospace) then
        -- マルチバイト文字(日本語)を含む: モデルで分節化
        local js = segment_fn(spseg_nospace)
        if splitpat == "" then
          segs = js
        else
          -- splitpat でさらに強制分割
          segs = {}
          for _, val in ipairs(js) do
            for _, part in ipairs(split_by_splitpat(val, punct_set)) do
              segs[#segs + 1] = part
            end
          end
        end
      else
        segs = { spseg_nospace }
      end
      spsegcols[#spsegcols + 1] = { segment = segs, col = col }
    end
    col = nextcol
  end

  -- スペース区切り segment 内の文節区切りを展開して col/colend を付ける
  local segcols = {}
  for _, sp in ipairs(spsegcols) do
    local c = sp.col
    for _, seg in ipairs(sp.segment) do
      local nextcol = c + #seg
      segcols[#segcols + 1] = { segment = seg, col = c, colend = nextcol - 1 }
      c = nextcol
    end
  end
  return segcols
end

---キャッシュをクリアする(バッファ変更時などに呼ぶ)。
function M.clear_cache()
  cache = {}
end

-- ---------------------------------------------------------------------------
-- 外部トークナイザ (Vibrato / Vaporetto) の結果組み立て
-- ---------------------------------------------------------------------------

---トークナイザの語列から、行内の各語の開始バイト位置を求める。
---語が行内に見つからない場合 (完全一致しない場合) は直前の語の直後を使う。
---@param line string
---@param words string[] 表層形
---@return number[] positions 各語の開始位置 (1始まりバイト)
function M.word_positions(line, words)
  local positions = {}
  local search_from = 1
  for i, w in ipairs(words) do
    local found = line:find(w, search_from, true)
    if not found then
      found = search_from
    end
    positions[i] = found
    search_from = found + #w
  end
  return positions
end

---トークナイザの語列を文節 SegmentCol[] に組み立てる。
---助詞・助動詞は前の語に結合し、splitpat の強制区切り文字は前の segment に
---残した上で直後を強制境界にする (split_line と同じ規則)。
---@param words string[] 表層形
---@param positions number[] 各語の開始位置 (1始まりバイト、M.word_positions)
---@param infos table[]|nil 各語の詳細 { pos, ... }
---@return SegmentCol[]
function M.words_to_segments(words, positions, infos)
  if #words == 0 then
    return {}
  end
  local vibrato = require("bunsetsu._commands.vibrato")
  local punct_set = get_punct_set(config.DATA.splitpat)
  local segcols = {}
  local start_col, end_col, seg_text

  local function flush()
    if seg_text then
      segcols[#segcols + 1] = { segment = seg_text, col = start_col, colend = end_col }
      seg_text = nil
    end
  end

  for i = 1, #words do
    local word = words[i]
    local pos = infos and infos[i] and infos[i].pos or ""
    if punct_set[word] and seg_text then
      -- 強制区切り文字は前の segment に残し、直後を強制境界にする
      end_col = positions[i] + #word - 1
      seg_text = seg_text .. word
      flush()
    elseif seg_text and vibrato.is_particle(pos) then
      -- 助詞・助動詞は前の語に結合
      end_col = positions[i] + #word - 1
      seg_text = seg_text .. word
    else
      flush()
      start_col = positions[i]
      end_col = positions[i] + #word - 1
      seg_text = word
    end
  end
  flush()
  return segcols
end

return M
