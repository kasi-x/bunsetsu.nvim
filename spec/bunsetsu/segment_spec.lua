describe("bunsetsu.segment (SegmentCol equivalent)", function()
  local segment = require("bunsetsu._core.segment")
  local config = require("bunsetsu._core.configuration")

  before_each(function()
    config.initialize_data_if_needed()
    config.resolve_data()
  end)

  describe("split_line()", function()
    it("segments a simple sentence with knbc_bunsetu", function()
      local segcols = segment.split_line("knbc_bunsetu", "これは文章です。")
      assert.are.same(2, #segcols)
      assert.are.same("これは", segcols[1].segment)
      assert.are.same(1, segcols[1].col)
      assert.are.same(9, segcols[1].colend)
      assert.are.same("文章です。", segcols[2].segment)
      assert.are.same(10, segcols[2].col)
      assert.are.same(24, segcols[2].colend)
    end)

    it("splits on spaces and computes byte columns", function()
      local segcols = segment.split_line(
        "knbc_bunsetu",
        "日本語の文章を 文節単位で 移動するテストです。"
      )
      assert.are.same(5, #segcols)
      assert.are.same("日本語の", segcols[1].segment)
      assert.are.same(1, segcols[1].col)
      -- 2番目はスペース2バイト + 1文字目
      assert.are.same("文章を", segcols[2].segment)
      assert.are.same(13, segcols[2].col)
      -- 3番目: 全角スペースで区切られた「文節単位で」は col=23 (21バイト + 全角スペース2バイト)
      assert.are.same("文節単位で", segcols[3].segment)
      assert.are.same(23, segcols[3].col)
    end)

    it("handles leading whitespace", function()
      local segcols =
        segment.split_line("knbc_bunsetu", "  行頭スペース付き 文章です。  ")
      assert.are.same("行頭スペース", segcols[1].segment)
      assert.are.same(3, segcols[1].col)
      assert.are.same("付き", segcols[2].segment)
      assert.are.same(21, segcols[2].col)
      assert.are.same("文章です。", segcols[3].segment)
      assert.are.same(28, segcols[3].col)
    end)

    it("returns empty table for empty/whitespace-only line", function()
      assert.are.same({}, segment.split_line("knbc_bunsetu", ""))
      assert.are.same({}, segment.split_line("knbc_bunsetu", "   "))
    end)

    it("does not split pure-ascii text", function()
      local segcols = segment.split_line("knbc_bunsetu", "hello world")
      assert.are.same(2, #segcols)
      assert.are.same("hello", segcols[1].segment)
      assert.are.same("world", segcols[2].segment)
    end)
  end)

  describe("segment_col_line() with cache", function()
    it("returns the same result from cache", function()
      local first = segment.segment_col_line("knbc_bunsetu", "これは文章です。")
      local second = segment.segment_col_line("knbc_bunsetu", "これは文章です。")
      assert.are.same(first, second)
    end)
  end)

  describe("splitpat (forced break pattern)", function()
    after_each(function()
      config.resolve_data({ splitpat = "[?!、。]" })
    end)

    it("splits after the configured characters by default", function()
      local segs = segment.split_line("knbc_bunsetu", "これ、です")
      assert.are.same("これ、", segs[1].segment)
    end)

    it("honors a custom character class", function()
      config.resolve_data({ splitpat = "[、]" })
      local segs = segment.split_line("knbc_bunsetu", "これ、テスト")
      assert.are.same("これ、", segs[1].segment)
    end)

    it("can be disabled with an empty pattern", function()
      config.resolve_data({ splitpat = "" })
      local segs = segment.split_line("knbc_bunsetu", "これは。テスト")
      local texts = vim.tbl_map(function(sc)
        return sc.segment
      end, segs)
      -- 強制分割は入らない (モデル自身の区切りのみ)
      assert.are.same({ "これは。", "テスト" }, texts)
    end)
  end)

  describe("word_positions()", function()
    it("locates each word in the line", function()
      local positions = segment.word_positions("これは文章です。", {
        "これ",
        "は",
        "文章",
        "です",
        "。",
      })
      assert.are.same({ 1, 7, 10, 16, 22 }, positions)
    end)

    it("falls back to the previous word end for unseen words", function()
      local positions =
        segment.word_positions("これは", { "これ", "は", "見つからない語" })
      -- 行内に見つからない語は直前の語の終端に置かれる
      assert.are.same({ 1, 7, 10 }, positions)
    end)

    it("returns an empty table for no words", function()
      assert.are.same({}, segment.word_positions("これは", {}))
    end)
  end)

  describe("words_to_segments() (external tokenizer assembly)", function()
    it("merges particles and attaches punctuation to the previous segment", function()
      local positions = segment.word_positions("これは文章です。", {
        "これ",
        "は",
        "文章",
        "です",
        "。",
      })
      local segcols = segment.words_to_segments(
        { "これ", "は", "文章", "です", "。" },
        positions,
        {
          { pos = "名詞" },
          { pos = "助詞" },
          { pos = "名詞" },
          { pos = "助動詞" },
          { pos = "記号" },
        }
      )
      assert.are.same(2, #segcols)
      assert.are.same("これは", segcols[1].segment)
      assert.are.same(1, segcols[1].col)
      assert.are.same(9, segcols[1].colend)
      assert.are.same("文章です。", segcols[2].segment)
      assert.are.same(10, segcols[2].col)
      assert.are.same(24, segcols[2].colend)
    end)

    it("keeps punctuation separate when splitpat is disabled", function()
      config.resolve_data({ splitpat = "" })
      local positions = segment.word_positions("これは文章です。", {
        "これ",
        "は",
        "文章",
        "です",
        "。",
      })
      local segcols = segment.words_to_segments(
        { "これ", "は", "文章", "です", "。" },
        positions,
        {
          { pos = "名詞" },
          { pos = "助詞" },
          { pos = "名詞" },
          { pos = "助動詞" },
          { pos = "記号" },
        }
      )
      local texts = vim.tbl_map(function(sc)
        return sc.segment
      end, segcols)
      assert.are.same({ "これは", "文章です", "。" }, texts)
    end)

    it("returns an empty table for no words", function()
      assert.are.same({}, segment.words_to_segments({}, {}, {}))
    end)
  end)
end)
