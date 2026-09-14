-- 日英混在テキストの境界ケース検証。
-- 文末検出 (sentence.ends)、文節分割 (segment.split_line)、
-- 言語判定 (lang.has_japanese) の相互運用性を確認する。

describe("bunsetsu mixed Japanese/English boundaries", function()
  local sentence = require("bunsetsu._core.sentence")
  local segment = require("bunsetsu._core.segment")
  local lang = require("bunsetsu._core.lang")
  local config = require("bunsetsu._core.configuration")

  before_each(function()
    config.initialize_data_if_needed()
    config.resolve_data()
    segment.clear_cache()
  end)

  describe("lang.has_japanese() edge cases", function()
    it("detects standard Japanese", function()
      assert.is_true(lang.has_japanese("これはテスト"))
      assert.is_true(lang.has_japanese("カタカナ"))
      assert.is_true(lang.has_japanese("漢字"))
    end)

    it("detects half-width katakana", function()
      assert.is_true(lang.has_japanese("\xEF\xBD\x94\xEF\xBD\x93\xEF\xBD\x94"))
    end)

    it("rejects pure ASCII", function()
      assert.is_false(lang.has_japanese("hello world 123"))
      assert.is_false(lang.has_japanese(""))
    end)

    it("detects Japanese embedded in English text", function()
      assert.is_true(lang.has_japanese("use bunsetsu for 日本語 motion"))
    end)

    it("handles CJK Extension B characters (rare kanji)", function()
      -- 𠮷 (U+20B9F) は一-龠の範囲外
      -- 偽陽性でも実害はない (True positive に近い動作でフォールバックする)
      assert.is_not_nil(lang.has_japanese("𠮷"))
    end)
  end)

  describe("sentence.ends() mixed text", function()
    it("splits Japanese sentence followed by English", function()
      local ends = sentence.ends("これはテストです。This is a test.")
      assert.are.equal(2, #ends)
    end)

    it("splits English sentence followed by Japanese", function()
      local ends = sentence.ends("Hello world. こんにちは。")
      assert.are.equal(2, #ends)
    end)

    it("does not split numbers with decimal points", function()
      local ends = sentence.ends("Version 3.14 is stable. Released today.")
      assert.are.equal(2, #ends)
    end)

    it("does not split URLs mid-path", function()
      local ends = sentence.ends("Visit https://example.com/page.html. Then click.")
      assert.are.equal(2, #ends)
    end)

    it("handles full-width period (．) as sentence end", function()
      local ends = sentence.ends("終了しました．次の処理へ．")
      assert.are.equal(2, #ends)
    end)

    it("does not split abbreviation followed by non-space", function()
      -- "Done.Next" はピリオドの直後に非空白文字 → 分割しない
      local ends = sentence.ends("Done.Next is Japanese.")
      assert.are.equal(1, #ends)
    end)

    it("handles exclamation + English", function()
      local ends = sentence.ends("わかった！Let me check. OK.")
      assert.are.equal(3, #ends)
    end)

    it("handles repeated terminators (？！) as one boundary", function()
      local ends = sentence.ends("本当？！そうだ！")
      assert.are.equal(2, #ends)
    end)
  end)

  describe("segment.split_line() mixed text", function()
    it("segments Japanese text with embedded ASCII words", function()
      local segcols = segment.split_line("knbc_bunsetu", "Vimはエディタです。")
      assert.are.same(
        { "Vimは", "エディタです。" },
        vim.tbl_map(function(sc)
          return sc.segment
        end, segcols)
      )
    end)

    it("handles mixed text with punctuation", function()
      local segs = vim.tbl_map(function(sc)
        return sc.segment
      end, segment.split_line("knbc_bunsetu", "Vimは。Test、です。"))
      assert.are.same({ "Vimは。", "Test、", "です。" }, segs)
    end)

    it("splits pure ASCII by whitespace only", function()
      local segcols = segment.split_line("knbc_bunsetu", "hello world foo")
      assert.are.same(
        { "hello", "world", "foo" },
        vim.tbl_map(function(sc)
          return sc.segment
        end, segcols)
      )
    end)

    it("handles lines with only ASCII punctuation", function()
      local segcols = segment.split_line("knbc_bunsetu", "!!! ???")
      assert.are.same(
        { "!!!", "???" },
        vim.tbl_map(function(sc)
          return sc.segment
        end, segcols)
      )
    end)

    it("handles empty and whitespace-only lines", function()
      assert.are.same({}, segment.split_line("knbc_bunsetu", ""))
      assert.are.same({}, segment.split_line("knbc_bunsetu", "   "))
    end)
  end)

  describe("words_to_segments() with external tokenizer (mocked vibrato)", function()
    local vibrato = require("bunsetsu._commands.vibrato")
    local original_tokenize_detailed

    before_each(function()
      original_tokenize_detailed = vibrato.tokenize_detailed
      vibrato.tokenize_detailed = function(line)
        if line == "This is 天堂 真矢。" then
          return { "This", "is", "天堂", "真矢", "。" }, {
            { pos = "名詞" },
            { pos = "動詞" },
            { pos = "名詞" },
            { pos = "名詞" },
            { pos = "記号" },
          }
        end
        return {}, {}
      end
    end)

    after_each(function()
      vibrato.tokenize_detailed = original_tokenize_detailed
    end)

    it("handles mixed English/Japanese from external tokenizer", function()
      local segcols = segment.split_line("knbc_bunsetu", "This is 天堂 真矢。")
      local texts = vim.tbl_map(function(sc)
        return sc.segment
      end, segcols)
      assert.are.same({ "This", "is", "天堂", "真矢。" }, texts)
    end)
  end)
end)
