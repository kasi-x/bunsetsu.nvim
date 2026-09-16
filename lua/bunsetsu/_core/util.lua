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

---fn をデバウンスしつつ呼ぶ関数を返す。呼び出し引数は fn へそのまま渡る。
---@param group number? augroup id (現状は未使用。将来的に autocmd 連携用)
---@param fn function デバウンスして実行する処理
---@param debounce number ms
---@return function
function M.debounce(group, fn, debounce)
  local timer = vim.uv.new_timer()
  return function(...)
    if timer:is_active() then
      timer:stop()
    end
    local args = { ... }
    timer:start(debounce, 0, function()
      vim.schedule(function()
        fn(unpack(args))
      end)
    end)
  end
end

return M
