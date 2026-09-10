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

    it("returns false when no boundary ahead at line start for b", function()
      -- backward では line が逆順。行頭 (searchOffset 逆順で len) からは移動なし
      local rev = ("これは文章です。"):reverse()
      assert.are.same(false, spider.pattern(rev, 24, "b"))
    end)

    it("returns false when no boundary ahead", function()
      -- 文節が1つしかない行では w の次が無い
      assert.are.same(false, spider.pattern("こんにちは", 1, "w"))
    end)
  end)

  describe("pattern() backward coordinates", function()
    it("returns reversed coordinate for b", function()
      -- backward では line が逆順、searchOffset も逆順座標。
      -- カーソルが「文章です。」(col10-24) の途中 col0=11 (1-based 12) のとき、
      -- 逆順座標 = 24 - 12 + 1 = 13
      -- `b` は「現在の文節 (文章です。) の先頭」= 元座標 10 へ移動する。
      -- その逆順座標 = 24 - 10 + 1 = 15
      local line = "これは文章です。"
      local rev = line:reverse()
      local result = spider.pattern(rev, 13, "b")
      assert.are.same(15, result)
    end)

    it("returns reversed coordinate for ge", function()
      -- ge: 「文章です。」の先頭 (1-based 10) ではなく、その前の文節「これは」の
      -- 終端 (1-based 9) へ移動。逆順座標 = 24 - 9 + 1 = 16
      local line = "これは文章です。"
      local rev = line:reverse()
      local result = spider.pattern(rev, 13, "ge")
      assert.are.same(16, result)
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
