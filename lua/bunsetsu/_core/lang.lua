---文字種 (日本語 / 英語) の判定。
--
-- 文末移動や autocmd の絞り込みなど、「日本語かどうか」で挙動を変える
-- 箇所の判定をここに一元化する。すべて Lua パターンのみで、ホットパスで
-- vim.fn を呼ばない。

local utf8 = require("bunsetsu._core.utf8")

local M = {}

---日本語 (かな・漢字) を含むとみなす文字クラス。
M.JP_PATTERN = "[ぁ-んァ-ヶー一-龠]"

---日本語 (かな・漢字) を含むか。
---@param s string
---@return boolean
function M.has_japanese(s)
  return s:find(M.JP_PATTERN) ~= nil
end

---かな・漢字の文字数を返す。
---@param s string
---@return number
function M.jp_count(s)
  local n = 0
  for ch in s:gmatch(utf8.charpattern) do
    if ch:find(M.JP_PATTERN) then
      n = n + 1
    end
  end
  return n
end

---ASCII の英字の数を返す。
---@param s string
---@return number
function M.ascii_letter_count(s)
  local _, n = s:gsub("%a", "")
  return n
end

---文字列の主たる文字種を返す。
---日本語 (かな・漢字) を 1 文字でも含めば "japanese"、無くて英字を含めば
---"english"、どちらも無ければ (数字・記号のみ、空文字列など) "other"。
---"Vimはエディタ" のような混在文は "japanese" になる。
---@param s string
---@return "japanese"|"english"|"other"
function M.script(s)
  if M.has_japanese(s) then
    return "japanese"
  end
  if s:find("%a") then
    return "english"
  end
  return "other"
end

return M
