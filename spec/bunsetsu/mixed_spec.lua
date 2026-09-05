describe("bunsetsu mixed Japanese/ASCII text", function()
  local segment = require("bunsetsu._core.segment")

  describe("segment_col_line() with mixed text", function()
    it("splits mixed text by TinySegmenter (knbc_bunsetu)", function()
      local segcols = segment.segment_col_line("knbc_bunsetu", "Vimはエディタです。")
      -- TinySegmenter が ASCII も含めて文節に分割する
      assert.are.same(
        { "Vimは", "エディタです。" },
        vim.tbl_map(function(sc)
          return sc.segment
        end, segcols)
      )
    end)

    it("keeps pure-ascii chunks intact", function()
      local segcols = segment.segment_col_line("knbc_bunsetu", "hello world")
      assert.are.same(2, #segcols)
      assert.are.same("hello", segcols[1].segment)
      assert.are.same("world", segcols[2].segment)
    end)

    it("splits ascii words within a mixed segment", function()
      local segcols = segment.segment_col_line("rwcp", "Vim は エディタです")
      assert.are.same(
        { "Vim", "は", "エディタ", "です" },
        vim.tbl_map(function(sc)
          return sc.segment
        end, segcols)
      )
    end)

    it("handles mixed text with punctuation", function()
      local segcols = segment.segment_col_line("knbc_bunsetu", "Vimは。Test、です。")
      local segs = vim.tbl_map(function(sc)
        return sc.segment
      end, segcols)
      -- splitpat で句読点の後でも分割される
      assert.is.truthy(vim.tbl_contains(segs, "Vimは。"))
    end)
  end)
end)
