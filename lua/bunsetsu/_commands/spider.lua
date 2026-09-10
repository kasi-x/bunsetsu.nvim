---nvim-spider 用カスタムパターン (TinySegmenter バックエンド)。
--
-- 同梱の文節区切りモデルで行を分割し、nvim-spider の customPatterns に
-- 渡す境界関数を提供する。spider は forward (w/e) のときはそのままの
-- line を、backward (b/ge) のときはバイト反転した line を渡してくるため、
-- backward は一度反転を戻してから分割し、結果を逆順座標に写像して返す。
--
-- 使い方:
-- >lua
--   require("spider").setup({
--     customPatterns = {
--       patterns = { require("bunsetsu._commands.spider").pattern },
--       overrideDefault = false,
--     },
--   })
--

local config = require("bunsetsu._core.configuration")
local segment = require("bunsetsu._core.segment")

local M = {}

---導入済みの nvim-spider が function patterns に対応しているか。
---bunsetsu の境界関数を customPatterns に登録するには、関数を受け取れる
---spider が必要 (本家には未マージの変更。非対応の spider では motion 時に
---エラーになる)。
---@return boolean
function M.supports_function_patterns()
  local ok, logic = pcall(require, "spider.motion-logic")
  if not ok then
    return false
  end
  -- function pattern を渡してエラーにならず、
  -- 「マッチ無し」(false) が返れば対応している
  local probe_ok, result = pcall(logic.getNextPosition, "probe", 1, "w", {
    customPatterns = {
      patterns = {
        function()
          return false
        end,
      },
      overrideDefault = true,
    },
    subwordMovement = true,
    skipInsignificantPunctuation = true,
  })
  return probe_ok and result == false
end

---設定されたモデルで行を文節分割する。
---@param line string
---@return SegmentCol[]
local function line_segments(line)
  return segment.segment_col_line(config.DATA.model or "knbc_bunsetu", line)
end

---spider の customPatterns 用の境界関数。
---line は現在行 (backward 時はバイト反転済み)、searchOffset は 1始まり
---バイト位置。次の文節境界の 1始まりバイト位置を返す。移動先が無ければ
---false を返す。
---@param line string
---@param searchOffset number
---@param key "w"|"e"|"b"|"ge"
---@return number|false
function M.pattern(line, searchOffset, key)
  key = key or "w"
  local backwards = key == "b" or key == "ge"

  -- backward では spider がバイト反転した line を渡すので元に戻す。
  -- バイト反転は UTF-8 を壊すが、再び :reverse() すると元のバイト列に戻る。
  local original = backwards and line:reverse() or line
  local segcols = line_segments(original)
  if #segcols == 0 then
    return false
  end

  -- 文節境界 (開始位置と終端位置)
  local boundaries = {}
  local boundaryEnds = {}
  for _, sc in ipairs(segcols) do
    boundaries[#boundaries + 1] = sc.col
    boundaryEnds[#boundaryEnds + 1] = sc.colend
  end

  -- key に応じて位置を調整 (終端位置 e/ge は boundaryEnds[i])
  local target = function(i)
    if key == "e" or key == "ge" then
      return boundaryEnds[i]
    end
    return boundaries[i]
  end

  if backwards then
    -- 逆順座標系: 反転済み行の座標で「searchOffset より大きい最小」を返す
    local candidates = {}
    for i in ipairs(boundaries) do
      local rev = #line - target(i) + 1
      if rev > searchOffset then
        candidates[#candidates + 1] = rev
      end
    end
    if #candidates == 0 then
      return false
    end
    return math.min(unpack(candidates))
  end

  local candidates = {}
  for i in ipairs(boundaries) do
    local t = target(i)
    if t > searchOffset then
      candidates[#candidates + 1] = t
    end
  end
  if #candidates == 0 then
    return false
  end
  return math.min(unpack(candidates))
end

return M
