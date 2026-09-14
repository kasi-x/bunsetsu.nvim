---文末 (sentence end) への移動モーション。
--
-- 文末・段落末の検出は _core.sentence (日本語 。！？… / 英語 . ! ? + 空白・
-- 行末、空行による段落区切り) に一任し、ここではカーソル移動だけを担当する。
-- 複数行にまたがって前方向・後方向に走査し、境界が見つからなければ
-- カーソルを動かさない。
--
-- 列位置はバイト位置 (Vim の col() と同じ 1始まり)。

local sentence = require("bunsetsu._core.sentence")
local util = require("bunsetsu._core.util")

local M = {}

---count 個先の境界 (文末または段落末) の位置を返す。
---カーソルが境界の上にあっても、それより後ろの境界を探す。
---@param count number
---@return { lnum: number, col: number }|nil
function M.next_end_pos(count)
  local cur = util.get_cursor()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local lnum, col = cur[1], cur[2] + 1

  for _ = 1, count do
    local target = sentence.next_boundary(lines, lnum, col)
    if not target then
      return nil
    end
    lnum, col = target.lnum, target.col
  end
  return { lnum = lnum, col = col }
end

---count 個前の境界 (文末または段落先頭) の位置を返す。
---@param count number
---@return { lnum: number, col: number }|nil
function M.prev_end_pos(count)
  local cur = util.get_cursor()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local lnum, col = cur[1], cur[2] + 1

  for _ = 1, count do
    local target = sentence.prev_boundary(lines, lnum, col)
    if not target then
      return nil
    end
    lnum, col = target.lnum, target.col
  end
  return { lnum = lnum, col = col }
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
