describe("bunsetsu.textobj (sentence & phrase regions)", function()
  local textobj = require("bunsetsu._commands.textobj")
  local full = require("bunsetsu._commands.full")

  before_each(function()
    full.invalidate()
  end)

  describe("sentence_region()", function()
    it("selects the sentence containing the cursor (outer)", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "一文目です。二文目です。" })
      vim.api.nvim_win_set_cursor(0, { 1, 4 }) -- 「一文目」の中
      assert.are.same({ 1, 1, 1, 18 }, textobj.sentence_region(true))
    end)

    it("inner excludes the sentence terminator", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "一文目です。二文目です。" })
      vim.api.nvim_win_set_cursor(0, { 1, 4 })
      assert.are.same({ 1, 1, 1, 15 }, textobj.sentence_region(false))
    end)

    it("cursor on the terminator stays in the ending sentence", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "一文目です。二文目です。" })
      vim.api.nvim_win_set_cursor(0, { 1, 17 }) -- 「一文目です。」の 。 (byte 18)
      assert.are.same({ 1, 1, 1, 18 }, textobj.sentence_region(true))
    end)

    it("selects the second sentence when the cursor is inside it", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "一文目です。二文目です。" })
      vim.api.nvim_win_set_cursor(0, { 1, 20 })
      assert.are.same({ 1, 19, 1, 36 }, textobj.sentence_region(true))
      assert.are.same({ 1, 19, 1, 33 }, textobj.sentence_region(false))
    end)

    it("spans lines when the first line has no sentence end", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章の", "続きです。" })
      vim.api.nvim_win_set_cursor(0, { 2, 1 })
      assert.are.same({ 1, 1, 2, 15 }, textobj.sentence_region(true))
      assert.are.same({ 1, 1, 2, 12 }, textobj.sentence_region(false))
    end)

    it("handles english text (inner excludes the period)", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Hello world. How are you?" })
      vim.api.nvim_win_set_cursor(0, { 1, 14 }) -- "How" の中 (byte 15)
      assert.are.same({ 1, 14, 1, 25 }, textobj.sentence_region(true))
      assert.are.same({ 1, 14, 1, 24 }, textobj.sentence_region(false))
    end)

    it("returns nil when no sentence end remains", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "文末のない行" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      assert.is_nil(textobj.sentence_region(true))
    end)
  end)

  describe("phrase_region()", function()
    it("selects the phrase under the cursor", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
      vim.api.nvim_win_set_cursor(0, { 1, 4 }) -- 「これは」の中
      assert.are.same({ 1, 1, 1, 9 }, textobj.phrase_region(false))
      vim.api.nvim_win_set_cursor(0, { 1, 11 }) -- 「文章です。」の中
      assert.are.same({ 1, 10, 1, 24 }, textobj.phrase_region(false))
    end)

    it("outer includes trailing whitespace", function()
      -- これは = 9 bytes、空白 = 1 byte、文章です。 = 11-25
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは 文章です。" })
      vim.api.nvim_win_set_cursor(0, { 1, 2 })
      assert.are.same({ 1, 1, 1, 9 }, textobj.phrase_region(false))
      assert.are.same({ 1, 1, 1, 10 }, textobj.phrase_region(true))
    end)

    it("cursor on whitespace selects the next phrase", function()
      -- これは = 1-9、空白 = 10、です = 11-16
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは です" })
      vim.api.nvim_win_set_cursor(0, { 1, 9 }) -- 空白の上 (byte 10)
      assert.are.same({ 1, 11, 1, 16 }, textobj.phrase_region(false))
    end)

    it("returns nil on an empty line", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      assert.is_nil(textobj.phrase_region(true))
    end)
  end)
end)
