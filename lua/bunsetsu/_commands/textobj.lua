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

---オブジェクトの範囲 (start〜stop) を spider 経由で確定する。
---visual mode のときは元のアンカー (getpos("v")) を固定し、カーソル側の端を
---オブジェクトの境界まで延長する (選択の置き換えではなく延長)。
---@param start { lnum: number, col: number } オブジェクトの始端 (1始まりバイト)
---@param stop { lnum: number, col: number } オブジェクトの終端 (1始まりバイト)
---@param opts? { inclusive?: boolean }
---@return boolean
local function apply_region(start, stop, opts)
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local ok, op = pcall(require, "spider.extras.operator-pending")
    if not ok then
      vim.notify(
        "bunsetsu: この機能には nvim-spider が必要です (選択範囲の確定を spider に委譲しています)",
        vim.log.levels.WARN
      )
      return false
    end
    local v = vim.fn.getpos("v")
    local anchor = { lnum = v[2], col = v[3] - 1 }
    local cursor = vim.api.nvim_win_get_cursor(0)
    local going_forward = cursor[1] > anchor.lnum
      or (cursor[1] == anchor.lnum and cursor[2] >= anchor.col)
    local far = going_forward and stop or start
    return op.setEndpoints({ anchor.lnum, anchor.col }, { far.lnum, far.col - 1 }, opts)
  end
  return M.select_range(start.lnum, start.col, stop.lnum, stop.col, opts)
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
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  -- 段落を跨がない (空行で止まる)。start は前の文末の直後の非空白文字
  local range = sentence.paragraph_sentence_range(lines, cur[1], cur[2] + 1)
  if not range then
    return nil
  end

  local s, e = range.start, range.stop

  -- 先頭の空白を読み飛ばす (outer / inner 共通)
  local il, ic = s.lnum, s.col
  while il <= e.lnum do
    local line = lines[il] or ""
    while ic <= #line do
      local b = line:byte(ic)
      if
        b == 0x20
        or b == 0x09
        or (b == 0xE3 and line:byte(ic + 1) == 0x80 and line:byte(ic + 2) == 0x80)
      then
        ic = ic + (b == 0xE3 and 3 or 1)
      else
        break
      end
    end
    if ic <= #line then
      break
    end
    il, ic = il + 1, 1
  end
  if il < e.lnum or (il == e.lnum and ic <= e.col) then
    s = { lnum = il, col = ic }
  end

  -- outer: 文末文字を含む。inner: 文末文字を除く
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
  return apply_region(
    { lnum = region[1], col = region[2] },
    { lnum = region[3], col = region[4] },
    { inclusive = true }
  )
end

---文節のテキストオブジェクト (iW / aW 相当)。
---@param outer boolean
---@return boolean
function M.phrase(outer)
  local region = M.phrase_region(outer)
  if not region then
    return false
  end
  return apply_region(
    { lnum = region[1], col = region[2] },
    { lnum = region[3], col = region[4] },
    { inclusive = true }
  )
end

return M
