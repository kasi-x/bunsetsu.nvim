---文 (sentence) の区切り検出。
--
-- 行ごとに文末のバイト位置を検出する。日本語の文末文字 (。！？…) は常に
-- 文末、英語の文末記号は「直後に空白または行末が続く」場合だけ文末とみなす
-- (そのため "3.14" や "U.S.A" を誤検出しない)。混在行では各候補ごとに
-- 規則を適用する。
--
-- 文末位置は、文末文字に加えて直後に続く閉じ括弧・引用符 (」』）など) の
-- 末尾バイトを指す。

local utf8 = require("bunsetsu._core.utf8")
local lang = require("bunsetsu._core.lang")

local M = {}

---日本語の文末文字。全角ピリオド (．) と半角ピリオド (｡) も含む。
M.END_CHARS = "。！？…．｡"

---文末文字の直後に続いてよい閉じ括弧・引用符。
M.CLOSERS = "」』）〕〉》\"'"

---文末の直後にこれらの接続表現が続いたら、括弧の中の文末とみなさない。
---「〜だ。」と言った / 「はい」という答え のような間接引用のための例外。
---fast-bunkai (bunkai) の IndirectQuoteException と同じ発想だが、ここでは
---「閉じ括弧の直後の文末」にのみ適用する (bunkai はすべての文末に適用する
---ため「。とにかく…」のような普通の文も誤って抑制する。移動用途では
---そちらの方が被害が大きい)。
---長い順に並べること (prefix マッチのため)。
M.QUOTE_CONTINUATIONS = {
  "くらいです",
  "くらいでし",
  "ほどでし",
  "くらいの",
  "という",
  "もあり",
  "って",
  "など",
  "て",
  "で",
  "の",
  "と",
  "に",
  "は",
  "が",
  "を",
  "も",
}
---prefix マッチに必要な最大文字数。
local QUOTE_LOOKAHEAD = 5

---ch が文末文字かどうか。
---@param ch string
---@return boolean
local function is_end_char(ch)
  return M.END_CHARS:find(ch, 1, true) ~= nil
end

---chars[i..] が間接引用の接続表現で始まるかどうか。
---@param chars string[]
---@param i number
---@return boolean
local function starts_with_continuation(chars, i)
  if not chars[i] then
    return false
  end
  local lookahead = table.concat(chars, "", i, math.min(i + QUOTE_LOOKAHEAD - 1, #chars))
  for _, p in ipairs(M.QUOTE_CONTINUATIONS) do
    if lookahead:sub(1, #p) == p then
      return true
    end
  end
  return false
end

---ch が文末になり得る ASCII (半角) 記号かどうか。
---"." と "．" は「直後に空白・行末 (または閉じ括弧の並びを挟んだ先の空白・
---行末) が続く」場合のみ。小数点・省略形を誤検出しないため。
---"!" / "?" は常に文末。
---@param ch string
---@param next_ch string|nil 次の文字 (行末なら nil)
---@return boolean

local function is_ascii_end(ch, prev_ch, next_ch)
  if ch == "." then
    -- 直前が日本語文字 (かな・漢字) の場合、ASCII ピリオドは日本語文の
    -- 句点として機能する。ただし直後に ASCII 英数字が続く場合は
    -- ファイル名・バージョン表記の可能性が高いので分割しない
    if prev_ch and lang.has_japanese(prev_ch) then
      return next_ch == nil or not next_ch:match("[%w.]")
    end
    return next_ch == nil
      or next_ch == " "
      or next_ch == "\t"
      or (M.CLOSERS:find(next_ch, 1, true) ~= nil)
  end
  return ch == "!" or ch == "?"
end

---ch が閉じ括弧・引用符かどうか。
---@param ch string
---@return boolean
local function is_closer(ch)
  return M.CLOSERS:find(ch, 1, true) ~= nil
end

---行ごとの ends() 結果キャッシュ (移動のたびに同じ行を再解析しない)。
---@type table<string, number[]>
local ends_cache = {}

---行内の文末のバイト位置 (1始まり) を昇順で返す。
---位置は文末文字 (とそれに続く閉じ括弧・引用符の並び) の最終バイト。
---@param line string
---@return number[]
function M.ends(line)
  if line == "" then
    return {}
  end
  local cached = ends_cache[line]
  if cached then
    return cached
  end

  -- 文字ごとに分解してバイトオフセットを記録する
  local chars = {} ---@type string[]
  local offsets = {} ---@type number[] 各文字のバイト開始位置 (1始まり)
  local offset = 0
  for ch in line:gmatch(utf8.charpattern) do
    chars[#chars + 1] = ch
    offsets[#chars] = offset + 1
    offset = offset + #ch
  end

  local ends = {}
  local n = #chars
  local i = 1
  while i <= n do
    local ch = chars[i]
    local end_i = nil
    if is_end_char(ch) then
      end_i = i
    elseif is_ascii_end(ch, i > 1 and chars[i - 1] or nil, i < n and chars[i + 1] or nil) then
      end_i = i
    end

    if end_i then
      -- 直後に続く文末文字 (…… / !! など) と閉じ括弧・引用符も文末に含める
      local j = end_i + 1
      while
        j <= n
        and (is_end_char(chars[j]) or is_closer(chars[j]) or chars[j] == "!" or chars[j] == "?")
      do
        end_i = j
        j = j + 1
      end
      -- 間接引用: 「〜だ。」と言った のように、閉じ括弧の直後の文末が
      -- 接続表現に続くときは文末としない (外側の文の文末だけが残る)
      local is_quoted = end_i > i and is_closer(chars[end_i]) and not is_end_char(chars[end_i])
      if not (is_quoted and starts_with_continuation(chars, j)) then
        ends[#ends + 1] = offsets[end_i] + #chars[end_i] - 1
      end
      i = j
    else
      i = i + 1
    end
  end
  ends_cache[line] = ends
  return ends
end

--------------------------------------------------------------------------------
-- 段落 (空行で区切られた塊) を考慮した境界
--------------------------------------------------------------------------------

---空行 (空白のみの行) かどうか。
---@param line string
---@return boolean
local function is_blank_line(line)
  return line:match("^%s*$") ~= nil
end

---行の最初の非空白バイト位置を返す (全て空白なら nil)。全角空白も含む。
---@param line string
---@return number|nil
local function first_non_blank(line)
  local i = 1
  while i <= #line do
    local b = line:byte(i)
    if b == 0x20 or b == 0x09 then
      i = i + 1
    elseif b == 0xE3 and line:byte(i + 1) == 0x80 and line:byte(i + 2) == 0x80 then
      i = i + 3
    else
      return i
    end
  end
  return nil
end

---行の最終非空白バイト位置を返す (全て空白なら nil)。
---@param line string
---@return number|nil
local function last_non_blank(line)
  local trimmed = line:gsub("%s+$", "")
  if trimmed == "" then
    return nil
  end
  return #trimmed
end

---(lnum, col) が (target_lnum, target_col) より後か。
---@param lnum number
---@param col number
---@param target_lnum number
---@param target_col number
---@return boolean
local function is_after(lnum, col, target_lnum, target_col)
  return lnum > target_lnum or (lnum == target_lnum and col > target_col)
end

---(lnum, col) 以降の最初の境界 (文末または段落末) を行配列から探す。
---段落末とは、段落の最終行の最終非空白文字。空行で段落が区切られる。
---@param lines string[] バッファの行配列
---@param lnum number 開始行 (1始まり)
---@param col number 開始位置 (1始まりバイト)
---@return { lnum: number, col: number }|nil
function M.next_boundary(lines, lnum, col)
  local paragraph_end = nil
  for l = lnum, #lines do
    local line = lines[l] or ""
    if is_blank_line(line) then
      if paragraph_end and is_after(paragraph_end.lnum, paragraph_end.col, lnum, col) then
        return paragraph_end
      end
      paragraph_end = nil
    else
      for _, pos in ipairs(M.ends(line)) do
        if is_after(l, pos, lnum, col) then
          return { lnum = l, col = pos }
        end
      end
      local last = last_non_blank(line)
      if last then
        paragraph_end = { lnum = l, col = last }
      end
    end
  end
  return nil
end

---(lnum, col) 以前の最後の境界 (文末または段落先頭) を行配列から探す。
---段落先頭とは、段落の最初の行の最初の非空白文字。
---@param lines string[] バッファの行配列
---@param lnum number 開始行 (1始まり)
---@param col number 開始位置 (1始まりバイト)
---@return { lnum: number, col: number }|nil
function M.prev_boundary(lines, lnum, col)
  local paragraph_start = nil
  local in_paragraph = false
  for l = lnum, 1, -1 do
    local line = lines[l] or ""
    if is_blank_line(line) then
      if in_paragraph and paragraph_start then
        if
          paragraph_start.lnum < lnum
          or (paragraph_start.lnum == lnum and paragraph_start.col < col)
        then
          return paragraph_start
        end
      end
      in_paragraph = false
      paragraph_start = nil
    else
      local ends = M.ends(line)
      for i = #ends, 1, -1 do
        local pos = ends[i]
        if l < lnum or (l == lnum and pos < col) then
          return { lnum = l, col = pos }
        end
      end
      local first = first_non_blank(line)
      if first then
        paragraph_start = { lnum = l, col = first }
        in_paragraph = true
      end
    end
  end
  return nil
end

---(lnum, col) を含む段落の中の、カーソルを含む文の範囲を返す。
---start は文の最初の非空白文字、stop は文末文字 (または段落末)。
---空白行を跨がない。
---@param lines string[] バッファの行配列
---@param lnum number
---@param col number
---@return nil|{ start: { lnum: number, col: number }, stop: { lnum: number, col: number } }
function M.paragraph_sentence_range(lines, lnum, col)
  -- カーソル行が空行なら、次の段落へ読み替える
  if lines[lnum] and is_blank_line(lines[lnum]) then
    local l = lnum
    while l <= #lines and (not lines[l] or is_blank_line(lines[l])) do
      l = l + 1
    end
    lnum, col = l, 1
  end

  -- 段落の上端
  local start = nil
  local l = lnum
  while l >= 1 and lines[l] and not is_blank_line(lines[l]) do
    local f = first_non_blank(lines[l])
    if f then
      start = { lnum = l, col = f }
    end
    l = l - 1
  end
  if not start then
    return nil
  end

  -- 段落内を前方向に走査し、カーソル以降の最初の文末で止める。
  -- カーソルより前の文末が出るたびに、その直後を次の文の始点として更新する
  local stop = nil
  l = start.lnum
  while l <= #lines and lines[l] and not is_blank_line(lines[l]) do
    local line = lines[l]
    local last = last_non_blank(line)
    if last then
      stop = { lnum = l, col = last }
    end
    for _, pos in ipairs(M.ends(line)) do
      if l > lnum or (l == lnum and pos >= col) then
        return { start = start, stop = { lnum = l, col = pos } }
      end
      start = { lnum = l, col = pos + 1 }
    end
    l = l + 1
  end
  return { start = start, stop = stop }
end

return M
