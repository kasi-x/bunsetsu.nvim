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

---count 個先の文末へカーソルを移動する。
---カーソルが文末の上にあっても、それより後ろの文末を探す。
---@param count number
---@return boolean 移動したか
function M.next_end(count)
  local cur = util.get_cursor()
  local cur_lnum, cur_col = cur[1], cur[2] + 1
  local last = vim.api.nvim_buf_line_count(0)

  local remaining = count
  for lnum = cur_lnum, last do
    for _, pos in ipairs(sentence.ends(util.line(lnum))) do
      if lnum > cur_lnum or pos > cur_col then
        remaining = remaining - 1
        if remaining == 0 then
          util.set_cursor(lnum, pos)
          return true
        end
      end
    end
  end
  return false
end

---count 個前の文末へカーソルを移動する。
---カーソルが文末の上にあっても、それより前の文末を探す。
---@param count number
---@return boolean 移動したか
function M.prev_end(count)
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
          util.set_cursor(lnum, pos)
          return true
        end
      end
    end
  end
  return false
end

return M
