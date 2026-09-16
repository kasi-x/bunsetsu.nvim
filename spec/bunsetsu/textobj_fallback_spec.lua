---nvim-spider 無しで動くテキストオブジェクトのフォールバック。
---選択範囲の確定を spider に委譲せず、visual selection を直接作る。
describe("bunsetsu.textobj without nvim-spider (fallback)", function()
  local textobj = require("bunsetsu._commands.textobj")
  local full = require("bunsetsu._commands.full")
  local ESC = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)

  before_each(function()
    full.invalidate()
    -- spider の extras を確実に無効化してフォールバック経路を通す
    package.preload["spider.extras.operator-pending"] = nil
    package.loaded["spider.extras.operator-pending"] = nil
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "一文目です。二文目です。" })
  end)

  after_each(function()
    if vim.fn.mode():match("^[vV\22]") then
      vim.cmd("normal! " .. ESC)
    end
    for _, key in ipairs({ "is", "as", "iW", "aW" }) do
      pcall(vim.keymap.del, "o", key, { buffer = 0 })
      pcall(vim.keymap.del, "x", key, { buffer = 0 })
    end
  end)

  describe("operator-pending", function()
    it("dis deletes the inner sentence", function()
      vim.keymap.set("o", "is", function()
        textobj.sentence(false)
      end, { buffer = 0 })
      vim.api.nvim_win_set_cursor(0, { 1, 20 }) -- 「二文目です。」の中 (byte 21)
      vim.fn.feedkeys("dis", "x")
      assert.are.same({ "一文目です。。" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("das deletes the outer sentence including the terminator", function()
      vim.keymap.set("o", "as", function()
        textobj.sentence(true)
      end, { buffer = 0 })
      vim.api.nvim_win_set_cursor(0, { 1, 4 })
      vim.fn.feedkeys("das", "x")
      assert.are.same({ "二文目です。" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("diW deletes the inner phrase", function()
      vim.keymap.set("o", "iW", function()
        textobj.phrase(false)
      end, { buffer = 0 })
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは 文章です。" })
      vim.api.nvim_win_set_cursor(0, { 1, 12 }) -- 「文章です。」の中 (byte 13)
      vim.fn.feedkeys("diW", "x")
      assert.are.same({ "これは " }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("yas yanks the sentence into a register", function()
      vim.keymap.set("o", "as", function()
        textobj.sentence(true)
      end, { buffer = 0 })
      vim.api.nvim_win_set_cursor(0, { 1, 20 })
      vim.fn.feedkeys("yas", "x")
      assert.are.equal("二文目です。", vim.fn.getreg('"'))
    end)

    it("respects the forced linewise motion (dVas)", function()
      vim.keymap.set("o", "as", function()
        textobj.sentence(true)
      end, { buffer = 0 })
      vim.api.nvim_buf_set_lines(
        0,
        0,
        -1,
        false,
        { "一文目です。二文目です。", "次の行" }
      )
      vim.api.nvim_win_set_cursor(0, { 1, 20 })
      vim.fn.feedkeys("dVas", "x")
      assert.are.same({ "次の行" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)
  end)

  describe("visual mode", function()
    it("keeps the anchor and extends to the sentence end", function()
      vim.api.nvim_win_set_cursor(0, { 1, 18 }) -- byte 19 (二文目の先頭)
      vim.cmd("normal! v")
      textobj.sentence(true)
      assert.are.equal("v", vim.fn.mode())
      assert.are.same(19, vim.fn.getpos("v")[3]) -- アンカーは固定 (1始まり)
      assert.are.same(36, vim.fn.getpos(".")[3]) -- 文末 (。の右端) まで延長
    end)

    it("extends backward to the sentence start", function()
      vim.api.nvim_win_set_cursor(0, { 1, 24 }) -- byte 25 (目) で v
      vim.cmd("normal! v")
      vim.api.nvim_win_set_cursor(0, { 1, 18 }) -- カーソルを文の先頭へ戻す
      textobj.sentence(false)
      assert.are.equal("v", vim.fn.mode())
      assert.are.same(25, vim.fn.getpos("v")[3]) -- アンカー
      assert.are.same(19, vim.fn.getpos(".")[3]) -- 二文目の始端まで延長
    end)

    it("aW extends the phrase selection keeping the anchor", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは 文章です。" })
      full.invalidate()
      vim.api.nvim_win_set_cursor(0, { 1, 10 }) -- byte 11 (文)
      vim.cmd("normal! v")
      textobj.phrase(true)
      assert.are.equal("v", vim.fn.mode())
      assert.are.same(11, vim.fn.getpos("v")[3])
      assert.are.same(25, vim.fn.getpos(".")[3]) -- 文章です。の。 (前の空白を含む)
    end)
  end)

  describe("normal mode", function()
    it("creates a charwise visual selection of the sentence", function()
      vim.api.nvim_win_set_cursor(0, { 1, 18 })
      textobj.sentence(true)
      assert.are.equal("v", vim.fn.mode())
      assert.are.same(19, vim.fn.getpos("v")[3]) -- 文の始端
      assert.are.same(36, vim.fn.getpos(".")[3]) -- 文の終端
    end)
  end)
end)
