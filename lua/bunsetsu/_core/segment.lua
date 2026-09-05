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

---splitpat (デフォルト '[^[:space:]　][?!、。]+\zs') で強制分割する。
---句読点(、。?! 等)の直後で分割する。
---@param s string
---@return string[]
local function split_by_splitpat(s)
  local result = {}
  local buf = {}
  local in_punct_run = false
  local prev_non_space = false
  for _, ch in utf8.codes(s) do
    local is_punct = ch == "?" or ch == "!" or ch == "、" or ch == "。"
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
  return config.splitpat
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
            for _, part in ipairs(split_by_splitpat(val)) do
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

return M
