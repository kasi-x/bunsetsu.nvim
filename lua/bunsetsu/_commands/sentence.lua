---文末 (sentence end) への移動モーション。
--
-- 文末の検出は _core.sentence.ends() (日本語 。！？… / 英語 . ! ? + 空白・
-- 行末の判定) に一任し、ここではカーソル移動だけを担当する。
-- 複数行にまたがって前方向・後方向に走査し、文末が見つからなければ
-- カーソルを動かさない。
--
-- 列位置はバイト位置 (Vim の col() と同じ 1始まり)。

local sentence = require("bunsetsu._core.sentence")
local util = require("bunsetsu._core.util")

local M = {}

---count 個先の文末の位置を返す。
---カーソルが文末の上にあっても、それより後ろの文末を探す。
---@param count number
---@return { lnum: number, col: number }|nil
function M.next_end_pos(count)
  local cur = util.get_cursor()
  local cur_lnum, cur_col = cur[1], cur[2] + 1
  local last = vim.api.nvim_buf_line_count(0)

  local remaining = count
  for lnum = cur_lnum, last do
    for _, pos in ipairs(sentence.ends(util.line(lnum))) do
      if lnum > cur_lnum or pos > cur_col then
        remaining = remaining - 1
        if remaining == 0 then
          return { lnum = lnum, col = pos }
        end
      end
    end
  end
  return nil
end

---count 個前の文末の位置を返す。
---@param count number
---@return { lnum: number, col: number }|nil
function M.prev_end_pos(count)
  local cur = util.get_cursor()
  local cur_lnum, cur_col = cur[1], cur[2] + 1

  local remaining = count
  for lnum = cur_lnum, 1, -1 do
    local ends = sentence.ends(util.line(lnum))
    for i = #ends, 1, -1 do
      local pos = ends[i]
      if lnum < cur_lnum or pos < cur_col then
        remaining = remaining - 1
        if remaining == 0 then
          return { lnum = lnum, col = pos }
        end
      end
    end
  end
  return nil
end

---count 個先の文末へカーソルを移動する。
---カーソルが文末の上にあっても、それより後ろの文末を探す。
---@param count number
---@return boolean 移動したか
function M.next_end(count)
  local target = M.next_end_pos(count)
  if not target then
    return false
  end
  util.set_cursor(target.lnum, target.col)
  return true
end

---count 個前の文末へカーソルを移動する。
---カーソルが文末の上にあっても、それより前の文末を探す。
---@param count number
---@return boolean 移動したか
function M.prev_end(count)
  local target = M.prev_end_pos(count)
  if not target then
    return false
  end
  util.set_cursor(target.lnum, target.col)
  return true
end

---operator-pending 用: カーソルから count 個先の文末 (を含む) までの範囲を
---operator に渡す。範囲の確定は nvim-spider の setEndpoints 経由。
---カーソル移動はしない。
---@param count number
---@return boolean 範囲を確定できたか
function M.operator_next_end(count)
  local target = M.next_end_pos(count)
  if not target then
    return false
  end
  local cur = util.get_cursor()
  local textobj = require("bunsetsu._commands.textobj")
  return textobj.select_range(cur[1], cur[2] + 1, target.lnum, target.col, { inclusive = true })
end

---operator-pending 用: カーソルから count 個前の文末 (を含む) までの範囲を
---operator に渡す。
---@param count number
---@return boolean 範囲を確定できたか
function M.operator_prev_end(count)
  local target = M.prev_end_pos(count)
  if not target then
    return false
  end
  local cur = util.get_cursor()
  local textobj = require("bunsetsu._commands.textobj")
  return textobj.select_range(target.lnum, target.col, cur[1], cur[2] + 1, { inclusive = true })
end

return M
