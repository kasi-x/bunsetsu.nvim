describe("bunsetsu.spider (nvim-spider custom pattern for bunsetsu)", function()
  local config = require("bunsetsu._core.configuration")
  local spider = require("bunsetsu._commands.spider")

  before_each(function()
    config.initialize_data_if_needed()
    config.resolve_data()
  end)

  describe("pattern()", function()
    it("returns the next bunsetsu start for w", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
      -- w: 「文章です。」先頭の 1-based byte = 10
      assert.are.same(10, spider.pattern("これは文章です。", 1, "w"))
    end)

    it("returns the bunsetsu end for e", function()
      -- e: 「これは」終端の 1-based byte = 9
      assert.are.same(9, spider.pattern("これは文章です。", 1, "e"))
    end)

    it("returns false when no boundary is before the cursor for b", function()
      -- 行頭 (searchOffset 1) より前には境界が無い
      assert.are.same(false, spider.pattern("これは文章です。", 1, "b", true))
    end)

    it("returns false when no boundary ahead", function()
      -- 文節が1つしかない行では w の次が無い
      assert.are.same(false, spider.pattern("こんにちは", 1, "w"))
    end)
  end)

  describe("pattern() with backwards = true", function()
    it("returns the previous bunsetsu start for b", function()
      local line = "これは文章です。"
      -- カーソルが「文章です。」(col10-24) の途中 byte 12 のとき、
      -- b はその文節の先頭 (byte 10) へ戻る
      assert.are.same(10, spider.pattern(line, 12, "b", true))
      -- カーソルが「文章です。」の先頭 (byte 10) のとき、
      -- b は前の文節「これは」の先頭 (byte 1) へ戻る
      assert.are.same(1, spider.pattern(line, 10, "b", true))
    end)

    it("returns the previous bunsetsu end for ge", function()
      local line = "これは文章です。"
      -- カーソルが「文章です。」の途中 byte 12 のとき、
      -- ge は前の文節「これは」の終端 (byte 9) へ戻る
      assert.are.same(9, spider.pattern(line, 12, "ge", true))
    end)
  end)

  describe("mixed ASCII/Japanese text (This is 天堂 真矢。) with TinySegmenter", function()
    -- この文は「真矢。」が1文節になる (vaporetto は「真矢」「。」に分割)。
    it("splits into This|is|天堂|真矢。", function()
      local segcols = require("bunsetsu._core.segment").segment_col_line(
        "knbc_bunsetu",
        "This is 天堂 真矢。"
      )
      local segs = {}
      for _, sc in ipairs(segcols) do
        segs[#segs + 1] = sc.segment
      end
      assert.are.same({ "This", "is", "天堂", "真矢。" }, segs)
    end)

    it("moves to the next bunsetsu start for w", function()
      -- 境界: This(1), is(6), 天堂(9), 真矢。(16)
      -- w (offset 1) から: is(6) -> 天堂(9) -> 真矢。(16)
      local line = "This is 天堂 真矢。"
      assert.are.same(6, spider.pattern(line, 1, "w"))
      assert.are.same(9, spider.pattern(line, 6, "w"))
      assert.are.same(16, spider.pattern(line, 9, "w"))
      -- 「真矢。」が最後の文節なので、その先頭からは次が無い
      assert.are.same(false, spider.pattern(line, 16, "w"))
    end)

    it("moves to the bunsetsu end for e", function()
      -- e: 各文節の終端
      -- This(4), is(7), 天堂(14), 真矢。(24)
      local line = "This is 天堂 真矢。"
      assert.are.same(4, spider.pattern(line, 1, "e"))
      assert.are.same(7, spider.pattern(line, 6, "e"))
      assert.are.same(14, spider.pattern(line, 9, "e"))
      assert.are.same(24, spider.pattern(line, 16, "e"))
    end)
  end)
  describe("supports_function_patterns()", function()
    local spider_mod = require("bunsetsu._commands.spider")

    after_each(function()
      package.preload["spider.motion-logic"] = nil
      package.loaded["spider.motion-logic"] = nil
      package.preload["spider"] = nil
      package.loaded["spider"] = nil
    end)

    it("returns false when nvim-spider is not installed", function()
      assert.is_false(spider_mod.supports_function_patterns())
    end)

    it("detects a spider that accepts function patterns", function()
      package.preload["spider.motion-logic"] = function()
        return {
          getNextPosition = function()
            return false
          end,
        }
      end
      assert.is_true(spider_mod.supports_function_patterns())
    end)

    it("returns false for a spider that rejects function patterns", function()
      package.preload["spider.motion-logic"] = function()
        return {
          getNextPosition = function(_, _, _, opts)
            -- 旧 spider 相当: function パターンで文字列関数を呼んでエラー
            error("bad argument #2 to 'find'")
          end,
        }
      end
      assert.is_false(spider_mod.supports_function_patterns())
    end)
  end)
end)
