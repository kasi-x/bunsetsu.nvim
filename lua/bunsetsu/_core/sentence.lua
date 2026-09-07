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

local M = {}

---日本語の文末文字。
M.END_CHARS = "。！？…"

---文末文字の直後に続いてよい閉じ括弧・引用符。
M.CLOSERS = "」』）〕〉》\"'"

---ch が文末文字かどうか。
---@param ch string
---@return boolean
local function is_end_char(ch)
  return M.END_CHARS:find(ch, 1, true) ~= nil
end

---ch が文末になり得る ASCII 記号かどうか。
---"." は直後に空白・行末が続く場合のみ (小数点・省略形を除外)。
---"!" / "?" は常に文末。
---@param ch string
---@param next_ch string|nil 次の文字 (行末なら nil)
---@return boolean
local function is_ascii_end(ch, next_ch)
  if #ch ~= 1 then
    return false
  end
  if ch == "." then
    return next_ch == nil or next_ch == " " or next_ch == "\t"
  end
  return ch == "!" or ch == "?"
end

---ch が閉じ括弧・引用符かどうか。
---@param ch string
---@return boolean
local function is_closer(ch)
  return M.CLOSERS:find(ch, 1, true) ~= nil
end

---行内の文末のバイト位置 (1始まり) を昇順で返す。
---位置は文末文字 (とそれに続く閉じ括弧・引用符の並び) の最終バイト。
---@param line string
---@return number[]
function M.ends(line)
  if line == "" then
    return {}
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
    elseif is_ascii_end(ch, i < n and chars[i + 1] or nil) then
      end_i = i
    end

    if end_i then
      -- 直後に続く文末文字 (…… / !! など) と閉じ括弧・引用符も文末に含める
      local j = end_i + 1
      while j <= n and (is_end_char(chars[j]) or is_closer(chars[j])) do
        end_i = j
        j = j + 1
      end
      ends[#ends + 1] = offsets[end_i] + #chars[end_i] - 1
      i = j
    else
      i = i + 1
    end
  end
  return ends
end

return M
