---文節移動モーション (spider 非依存)。
--
-- segment.segment_col_line で行の文節境界を取得し、カーソルを移動する。
-- spider の customPatterns よりもシンプル (句読点スキップやサブワード移動
-- はない) が、依存なしで動作する。spider が導入されている場合は spider の
-- customPatterns 経由でより高精度な移動が可能。
--
-- 列位置はバイト位置 (Vim の col() と同じ 1始まり)。

local config = require("bunsetsu._core.configuration")
local segment = require("bunsetsu._core.segment")

local M = {}

---count 個先の境界へカーソルを移動する。
---段階的に行を走査し、見つからなければカーソルを動かさない。
---@param count number 移動する境界数
---@param forwards boolean true = 前方向
---@param to_end boolean true = 文節の終端へ (e/ge)、false = 開始へ (w/b)
---@return boolean 移動したか
local function jump(count, start_lnum, start_col, forwards, to_end)
  local model = config.current_model()
  local line_count = vim.api.nvim_buf_line_count(0)
  local step = forwards and 1 or -1
  local stop_line = forwards and line_count + 1 or 0

  local remaining = count
  local l = start_lnum
  while l ~= stop_line do
    local line = vim.api.nvim_buf_get_lines(0, l - 1, l, false)[1] or ""
    local segcols = segment.segment_col_line(model, line)

    -- 走査順を決定 (backward は逆順)
    local indices = {}
    for i = 1, #segcols do
      indices[#indices + 1] = i
    end
    if not forwards then
      local rev = {}
      for i = #indices, 1, -1 do
        rev[#rev + 1] = indices[i]
      end
      indices = rev
    end

    for _, idx in ipairs(indices) do
      local sc = segcols[idx]
      local target = to_end and sc.colend or sc.col
      local is_candidate
      if forwards then
        is_candidate = l > start_lnum or target > start_col
      else
        is_candidate = l < start_lnum or target < start_col
      end
      if is_candidate then
        remaining = remaining - 1
        if remaining == 0 then
          vim.api.nvim_win_set_cursor(0, { l, target - 1 })
          return true
        end
      end
    end

    l = l + step
  end
  return false
end

---count 個先の文節の開始位置へカーソルを移動する (w 相当)。
---@param count number
---@return boolean 移動したか
function M.next_start(count)
  local c = vim.api.nvim_win_get_cursor(0)
  return jump(count, c[1], c[2] + 1, true, false)
end

---count 個前の文節の開始位置へカーソルを移動する (b 相当)。
---@param count number
---@return boolean 移動したか
function M.prev_start(count)
  local c = vim.api.nvim_win_get_cursor(0)
  return jump(count, c[1], c[2] + 1, false, false)
end

---count 個先の文節の終端へカーソルを移動する (e 相当)。
---@param count number
---@return boolean 移動したか
function M.next_end(count)
  local c = vim.api.nvim_win_get_cursor(0)
  return jump(count, c[1], c[2] + 1, true, true)
end

---count 個前の文節の終端へカーソルを移動する (ge 相当)。
---@param count number
---@return boolean 移動したか
function M.prev_end(count)
  local c = vim.api.nvim_win_get_cursor(0)
  return jump(count, c[1], c[2] + 1, false, true)
end

return M
