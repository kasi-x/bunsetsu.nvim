---テキストオブジェクト (文・文節)。
--
-- 範囲の確定 (選択開始・selection 設定・virtualedit・強制モーションの処理)
-- は nvim-spider の setEndpoints (spider.extras.operator-pending) に委譲する。
-- そのため operator-pending と visual mode の両方で動作する。
--
-- 使い方 (ユーザー設定例):
-- >lua
--   local textobj = require("bunsetsu._commands.textobj")
--   vim.keymap.set({ "x", "o" }, "is", function() textobj.sentence(false) end,
--     { desc = "bunsetsu: inner sentence" })
--   vim.keymap.set({ "x", "o" }, "as", function() textobj.sentence(true) end,
--     { desc = "bunsetsu: sentence" })
--   vim.keymap.set({ "x", "o" }, "iW", function() textobj.phrase(false) end,
--     { desc = "bunsetsu: inner bunsetsu" })
--   vim.keymap.set({ "x", "o" }, "aW", function() textobj.phrase(true) end,
--     { desc = "bunsetsu: bunsetsu" })
--

local config = require("bunsetsu._core.configuration")
local full = require("bunsetsu._commands.full")
local sentence = require("bunsetsu._core.sentence")
local utf8 = require("bunsetsu._core.utf8")
local util = require("bunsetsu._core.util")

local M = {}

---範囲を spider 経由で選択する。
---@param lnum1 number
---@param col1 number 1始まりバイト
---@param lnum2 number
---@param col2 number 1始まりバイト
---@param opts? { inclusive?: boolean }
---@return boolean
function M.select_range(lnum1, col1, lnum2, col2, opts)
  local ok, op = pcall(require, "spider.extras.operator-pending")
  if not ok then
    vim.notify(
      "bunsetsu: この機能には nvim-spider が必要です (選択範囲の確定を spider に委譲しています)",
      vim.log.levels.WARN
    )
    return false
  end
  return op.setEndpoints({ lnum1, col1 - 1 }, { lnum2, col2 - 1 }, opts)
end

---(lnum, col) 以降で最初の非空白文字の位置を返す。空行は読み飛ばす。
---@param lnum number
---@param col number
---@return { lnum: number, col: number }|nil
local function first_non_blank(lnum, col)
  local last = vim.api.nvim_buf_line_count(0)
  for l = lnum, last do
    local line = util.line(l)
    local pos = util.next_non_space(line, l == lnum and col or 1)
    if pos then
      return { lnum = l, col = pos }
    end
  end
  return nil
end

---cursor 位置以降の最初の文末 (cursor が文末の上ならその文末) を返す。
---@param lnum number
---@param col number
---@return { lnum: number, col: number }|nil
local function next_end_from(lnum, col)
  local last = vim.api.nvim_buf_line_count(0)
  for l = lnum, last do
    for _, pos in ipairs(sentence.ends(util.line(l))) do
      if l > lnum or pos >= col then
        return { lnum = l, col = pos }
      end
    end
  end
  return nil
end

---cursor 位置より前の最後の文末を返す。
---@param lnum number
---@param col number
---@return { lnum: number, col: number }|nil
local function prev_end_before(lnum, col)
  for l = lnum, 1, -1 do
    local ends = sentence.ends(util.line(l))
    for i = #ends, 1, -1 do
      if l < lnum or ends[i] < col then
        return { lnum = l, col = ends[i] }
      end
    end
  end
  return nil
end

---文末位置から、文末文字・閉じ括弧・空白を除いた「文の内容」の終端を返す。
---全文が記号のときは nil。
---@param lnum number
---@param end_col number
---@return { lnum: number, col: number }|nil
local function sentence_inner_end(lnum, end_col)
  local line = util.line(lnum)
  local chars, offsets = {}, {}
  local offset = 0
  for ch in line:gmatch(utf8.charpattern) do
    if offset + #ch > end_col then
      break
    end
    chars[#chars + 1] = ch
    offsets[#chars] = offset + 1
    offset = offset + #ch
  end

  local function is_trimmed(ch)
    return sentence.END_CHARS:find(ch, 1, true) ~= nil
      or sentence.CLOSERS:find(ch, 1, true) ~= nil
      or ch == " "
      or ch == "\t"
      or ch == "."
      or ch == "!"
      or ch == "?"
  end

  local j = #chars
  while j >= 1 and is_trimmed(chars[j]) do
    j = j - 1
  end
  if j < 1 then
    return nil
  end
  return { lnum = lnum, col = offsets[j] + #chars[j] - 1 }
end

---cursor 位置を含む文の範囲を返す。
---outer が true なら文末文字・閉じ括弧を含み、false なら文の内容のみ
---(文末文字と周囲の空白を除く)。
---@param outer boolean
---@return { [1]: number, [2]: number, [3]: number, [4]: number }|nil
function M.sentence_region(outer)
  local cur = util.get_cursor()
  local cur_lnum, cur_col = cur[1], cur[2] + 1

  local e = next_end_from(cur_lnum, cur_col)
  if not e then
    return nil
  end

  local p = prev_end_before(cur_lnum, cur_col)
  local s = p and first_non_blank(p.lnum, p.col + 1) or first_non_blank(1, 1)
  if not s then
    return nil
  end

  if outer then
    return { s.lnum, s.col, e.lnum, e.col }
  end

  local ie = sentence_inner_end(e.lnum, e.col) or e
  -- inner が start を追い越す場合 (文が記号のみなど) は outer にフォールバック
  if ie.lnum == s.lnum and ie.col < s.col then
    ie = e
  end
  return { s.lnum, s.col, ie.lnum, ie.col }
end

---cursor 位置を含む文節の範囲を返す。
---outer が true なら後続の空白を含める (無ければ前方の空白)。
---cursor が空白の上のときは次の文節、無ければ前の文節を選ぶ。
---@param outer boolean
---@return { [1]: number, [2]: number, [3]: number, [4]: number }|nil
function M.phrase_region(outer)
  local cur = util.get_cursor()
  local lnum, col = cur[1], cur[2] + 1
  local model = config.DATA.model or "knbc_bunsetu"
  local segcols = full.segcols(model, lnum)
  if #segcols == 0 then
    return nil
  end

  local chosen
  for _, sc in ipairs(segcols) do
    if sc.col <= col and col <= sc.colend then
      chosen = sc
      break
    end
  end
  if not chosen then
    for _, sc in ipairs(segcols) do
      if sc.col > col then
        chosen = sc
        break
      end
    end
  end
  if not chosen then
    chosen = segcols[#segcols]
  end

  local s, e = chosen.col, chosen.colend
  if outer then
    local line = util.line(lnum)
    -- 後続の空白 (半角・タブ・全角) を含める
    local e2 = e
    while e2 < #line do
      local b = line:byte(e2 + 1)
      if b == 0x20 or b == 0x09 then
        e2 = e2 + 1
      elseif b == 0xE3 and line:byte(e2 + 2) == 0x80 and line:byte(e2 + 3) == 0x80 then
        e2 = e2 + 3
      else
        break
      end
    end
    if e2 > e then
      e = e2
    else
      -- 後続が無ければ前方の空白を含める
      local s2 = s - 1
      while s2 >= 1 do
        local b = line:byte(s2)
        if b == 0x20 or b == 0x09 then
          s2 = s2 - 1
        elseif
          line:byte(s2) == 0xE3
          and line:byte(s2 + 1) == 0x80
          and line:byte(s2 + 2) == 0x80
        then
          s2 = s2 - 3
        else
          break
        end
      end
      s = s2 + 1
    end
  end
  return { lnum, s, lnum, e }
end

---文のテキストオブジェクト (is / as 相当)。
---spider の setEndpoints で選択範囲を確定する。
---@param outer boolean
---@return boolean
function M.sentence(outer)
  local region = M.sentence_region(outer)
  if not region then
    return false
  end
  return M.select_range(region[1], region[2], region[3], region[4], { inclusive = true })
end

---文節のテキストオブジェクト (iW / aW 相当)。
---@param outer boolean
---@return boolean
function M.phrase(outer)
  local region = M.phrase_region(outer)
  if not region then
    return false
  end
  return M.select_range(region[1], region[2], region[3], region[4], { inclusive = true })
end

return M
