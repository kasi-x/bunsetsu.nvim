describe("bunsetsu.util (pure Lua helpers)", function()
  local util = require("bunsetsu._core.util")

  describe("cursor_pos()", function()
    it("converts 1-based byte col to cursor { lnum, col0 }", function()
      assert.are.same({ 3, 9 }, util.cursor_pos(3, 10))
    end)
  end)

  describe("line() / get_cursor() / set_cursor()", function()
    it("reads the current buffer line", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "テスト行" })
      assert.are.equal("テスト行", util.line(1))
      assert.are.equal("", util.line(99))
    end)

    it("round-trips the cursor position", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは" })
      util.set_cursor(1, 4)
      local cur = util.get_cursor()
      assert.are.equal(1, cur[1])
      assert.are.equal(3, cur[2]) -- 0始まりバイト
    end)
  end)
  describe("debounce()", function()
    it("coalesces repeated calls into one run with the last arguments", function()
      local calls = {}
      local d = util.debounce(nil, function(x)
        calls[#calls + 1] = x
      end, 20)
      d(1)
      d(2)
      d(3)
      vim.wait(200, function()
        return #calls > 0
      end)
      assert.are.equal(1, #calls) -- まとめられて 1 回だけ実行される
      assert.are.equal(3, calls[1]) -- 最後の引数で実行される
    end)

    it("runs again for calls after the window", function()
      local calls = {}
      local d = util.debounce(nil, function(x)
        calls[#calls + 1] = x
      end, 10)
      d(1)
      vim.wait(200, function()
        return #calls > 0
      end)
      d(2)
      vim.wait(200, function()
        return #calls > 1
      end)
      assert.are.same({ 1, 2 }, calls)
    end)
  end)
end)
