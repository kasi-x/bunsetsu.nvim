describe("bunsetsu.vaporetto", function()
  local config = require("bunsetsu._core.configuration")
  local vaporetto = require("bunsetsu._commands.vaporetto")

  before_each(function()
    config.initialize_data_if_needed()
    config.resolve_data()
  end)

  after_each(function()
    vaporetto.clear_cache()
  end)

  describe("is_particle()", function()
    it("detects common particles", function()
      assert.is_true(vaporetto.is_particle("は"))
      assert.is_true(vaporetto.is_particle("を"))
      assert.is_true(vaporetto.is_particle("に"))
      assert.is_true(vaporetto.is_particle("の"))
    end)

    it("returns false for non-particles", function()
      assert.is_false(vaporetto.is_particle("東京"))
      assert.is_false(vaporetto.is_particle("エディタ"))
      assert.is_false(vaporetto.is_particle("文章"))
    end)
  end)

  describe("tokenize()", function()
    it("returns empty when no model is configured", function()
      config.resolve_data({ vaporetto = { cmd = "predict", model = "" } })
      local words, positions = vaporetto.tokenize("これは文章です。")
      assert.are.same({}, words)
      assert.are.same({}, positions)
    end)
  end)

  describe("pattern()", function()
    -- tokenize をモックして、モデル無しでも境界計算を検証する
    local original_tokenize

    before_each(function()
      original_tokenize = vaporetto.tokenize
    end)

    after_each(function()
      vaporetto.tokenize = original_tokenize
    end)

    it("word mode uses each word start as a boundary", function()
      vaporetto.tokenize = function(line)
        if line == "ヴェネツィアはイタリアにあります。" then
          return { "ヴェネツィア", "は", "イタリア", "に", "あり", "ます", "。" }, {
            1,
            19,
            22,
            34,
            37,
            43,
            49,
          }
        end
        return {}, {}
      end
      local pat = vaporetto.pattern("word")
      local line = "ヴェネツィアはイタリアにあります。"
      -- 単語境界: ヴェネツィア(1), は(19), イタリア(22), に(34)...
      -- w (offset 1) より後の最初の境界 = 19 (「は」)
      assert.are.same(19, pat(line, 1, "w"))
    end)

    it("bunsetsu mode merges particles into the previous word", function()
      vaporetto.tokenize = function(line)
        if line == "ヴェネツィアはイタリアにあります。" then
          return { "ヴェネツィア", "は", "イタリア", "に", "あり", "ます", "。" }, {
            1,
            19,
            22,
            34,
            37,
            43,
            49,
          }
        end
        return {}, {}
      end
      local pat = vaporetto.pattern("bunsetsu")
      local line = "ヴェネツィアはイタリアにあります。"
      -- 助詞「は」「に」を結合 → 境界: ヴェネツィア(1), イタリア(22), あり(37)...
      -- w (offset 1) より後の最初の境界 = 22 (「イタリア」)
      assert.are.same(22, pat(line, 1, "w"))
    end)

    it("returns false when tokenize produces no words", function()
      vaporetto.tokenize = function()
        return {}, {}
      end
      local pat = vaporetto.pattern("word")
      assert.is_false(pat("何かの行", 1, "w"))
    end)
  end)

  describe("mixed ASCII/Japanese text (This is 天堂 真矢。)", function()
    -- tokenize をモックして、混在文章の境界を検証する
    local original_tokenize

    before_each(function()
      original_tokenize = vaporetto.tokenize
      vaporetto.tokenize = function(line)
        if line == "This is 天堂 真矢。" then
          return { "This", "is", "天堂", "真矢", "。" }, { 1, 6, 9, 16, 22 }
        end
        return {}, {}
      end
    end)

    after_each(function()
      vaporetto.tokenize = original_tokenize
    end)

    it("word mode moves through ASCII and Japanese words", function()
      local pat = vaporetto.pattern("word")
      local line = "This is 天堂 真矢。"
      -- 境界: This(1), is(6), 天堂(9), 真矢(16), 。(22)
      -- w (offset 1) から: is(6) -> 天堂(9) -> 真矢(16) -> 。(22)
      assert.are.same(6, pat(line, 1, "w"))
      assert.are.same(9, pat(line, 6, "w"))
      assert.are.same(16, pat(line, 9, "w"))
      assert.are.same(22, pat(line, 16, "w"))
    end)

    it("bunsetsu mode keeps the same boundaries for this text", function()
      local pat = vaporetto.pattern("bunsetsu")
      local line = "This is 天堂 真矢。"
      -- 助詞を含まない文なので word モードと同じ境界
      assert.are.same(6, pat(line, 1, "w"))
      assert.are.same(9, pat(line, 6, "w"))
      assert.are.same(16, pat(line, 9, "w"))
      assert.are.same(22, pat(line, 16, "w"))
    end)
  end)
end)
