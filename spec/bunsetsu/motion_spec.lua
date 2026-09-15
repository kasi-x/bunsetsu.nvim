describe("bunsetsu.motion (phrase motion without spider)", function()
  local motion = require("bunsetsu._commands.motion")
  local config = require("bunsetsu._core.configuration")

  before_each(function()
    config.initialize_data_if_needed()
    config.resolve_data()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "これは文章です。次の文です。",
      "三行目のテキスト。",
    })
  end)

  it("next_start moves to the next phrase start", function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    assert.is_true(motion.next_start(1))
    -- 「文章です。」の開始 (byte 10 → col0 9)
    assert.are.same({ 1, 9 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("prev_start moves backward", function()
    vim.api.nvim_win_set_cursor(0, { 1, 20 })
    assert.is_true(motion.prev_start(1))
    local col = vim.api.nvim_win_get_cursor(0)[2]
    assert.is_true(col < 20)
  end)

  it("next_end moves to the phrase end", function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    assert.is_true(motion.next_end(1))
    local col = vim.api.nvim_win_get_cursor(0)[2]
    assert.is_true(col > 0)
  end)

  it("returns false at buffer end", function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    -- 最終行の最後の文節以降に移動先がないことを確認
    local result = motion.next_start(999)
    assert.is_false(result)
  end)

  it("works across lines", function()
    -- 1 行目の最後の文節にカーソルを置いて次の行へ
    local line1_len = #vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
    vim.api.nvim_win_set_cursor(0, { 1, line1_len - 1 })
    assert.is_true(motion.next_start(1))
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    assert.are.equal(2, lnum)
  end)
end)
