---純 Lua の高速ヘルパ群。ホットパスでは vim.fn.* を呼ばずにバッファ/カーソル
---操作を行う (flash.nvim と同様の方針)。

local M = {}

---1始まりのバイト列位置からカーソルの (lnum, col0) へ変換する。
---nvim_win_get_cursor の col は 0始まりバイト位置。
---@param lnum number
---@param col number 1始まりバイト位置
---@return number[] { lnum, col0 }
function M.cursor_pos(lnum, col)
  return { lnum, col - 1 }
end

---現在のバッファから行文字列を取得する。
---@param lnum number 1始まり
---@return string
function M.line(lnum)
  return vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
end

---現在のカーソル位置を { lnum, col0 } で返す。
---@return number[]
function M.get_cursor()
  return vim.api.nvim_win_get_cursor(0)
end

---カーソルを移動する。col は 1始まりバイト位置。
---@param lnum number
---@param col number 1始まりバイト位置
function M.set_cursor(lnum, col)
  vim.api.nvim_win_set_cursor(0, M.cursor_pos(lnum, col))
end

---カーソルを移動する。col0 は 0始まりバイト位置。
---@param lnum number
---@param col0 number
function M.set_cursor0(lnum, col0)
  vim.api.nvim_win_set_cursor(0, { lnum, col0 })
end

---行のバイト長を返す。Vim の col('$') は #line+1。
---@param line string
---@return number
function M.line_len(line)
  return #line
end

---行末にカーソルがあるかどうか。col0 が行のバイト長と一致するとき行末。
---@param line string
---@param col0 number
---@return boolean
function M.at_line_end(line, col0)
  return col0 >= #line
end

---ASCII 空白 (space, tab, \r, \n, \v, \f) かどうか
---@param b number バイト値
---@return boolean
local function is_ascii_space(b)
  return b == 0x20 or (b >= 0x09 and b <= 0x0D)
end

---col1 (1始まりバイト位置) 以降で最初の非空白文字のバイト位置を返す。
---見つからなければ nil。空白は ASCII 空白と全角スペース(U+3000)を対象にする。
---@param line string
---@param col1 number
---@return number|nil
function M.next_non_space(line, col1)
  local i = col1
  local len = #line
  while i <= len do
    local b = line:byte(i)
    if is_ascii_space(b) then
      i = i + 1
    elseif b == 0xE3 and line:byte(i + 1) == 0x80 and line:byte(i + 2) == 0x80 then
      i = i + 3
    else
      return i
    end
  end
  return nil
end

---col1 (1始まりバイト位置) より前で最後の非空白文字のバイト位置を返す。
---見つからなければ nil。
---@param line string
---@param col1 number
---@return number|nil
function M.prev_non_space(line, col1)
  local i = col1 - 1
  while i >= 1 do
    local b = line:byte(i)
    if is_ascii_space(b) then
      i = i - 1
    elseif b >= 0x80 and b < 0xC0 then
      -- マルチバイト文字の継続バイトはスキップして先頭へ
      i = i - 1
    elseif b == 0xE3 and line:byte(i + 1) == 0x80 and line:byte(i + 2) == 0x80 then
      i = i - 1
    else
      return i
    end
  end
  return nil
end

---バッファ変更後に全文キャッシュを無効化する (デバウンス付き)。
---@param group number augroup id
---@param fn function 無効化処理
---@param debounce number ms
function M.debounce(group, fn, debounce)
  local timer = vim.uv.new_timer()
  return function()
    if timer:is_active() then
      timer:stop()
    end
    timer:start(debounce, 0, function()
      vim.schedule(function()
        fn()
      end)
    end)
  end
end

return M
