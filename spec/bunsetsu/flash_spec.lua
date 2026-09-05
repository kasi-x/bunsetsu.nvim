describe("bunsetsu.flash (flash.nvim integration matcher)", function()
  local full = require("bunsetsu._commands.full")
  local flash = require("bunsetsu._commands.plugins.flash")

  before_each(function()
    full.invalidate()
  end)

  it("matcher() returns FlashMatch-like positions for the current buffer", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "これは文章です。",
      "Vimはエディタです。",
    })
    local matcher = flash.matcher("knbc_bunsetu")
    local matches = matcher(vim.api.nvim_get_current_win(), {})
    -- 文節 4 個 (これは/文章です。/Vimは/エディタです。)
    assert.are.same(4, #matches)
    -- pos は 0始まりバイト位置
    assert.are.same({ 1, 0 }, matches[1].pos)
    -- 「これは」colend=9 → 0始まりでは 8
    assert.are.same({ 1, 8 }, matches[1].end_pos)
    assert.are.same("これは", matches[1].text)
    -- 2行目の先頭 segment
    assert.are.same({ 2, 0 }, matches[3].pos)
  end)

  it("matcher() returns empty for a non-current buffer window", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
    local other_buf = vim.api.nvim_create_buf(true, false)
    local win = vim.api.nvim_open_win(other_buf, false, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 10,
      height = 1,
    })
    local matcher = flash.matcher("knbc_bunsetu")
    local matches = matcher(win, {})
    assert.are.same(0, #matches)
    vim.api.nvim_win_close(win, true)
  end)

  it("jump() calls flash.jump() with the matcher", function()
    local flash_called = nil
    package.loaded["flash"] = {
      jump = function(opts)
        flash_called = opts
      end,
    }
    flash.jump({})
    assert.is_truthy(flash_called)
    assert.is_function(flash_called.matcher)
    package.loaded["flash"] = nil
  end)
end)
