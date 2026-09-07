describe("bunsetsu.sentence (sentence end detection)", function()
  local sentence = require("bunsetsu._core.sentence")

  describe("ends() for japanese text", function()
    it("finds every sentence end character", function()
      -- これはテストです。(9 chars = 27 bytes) 次の文です。(6 chars = 18 bytes)
      assert.are.same({ 27, 45 }, sentence.ends("これはテストです。次の文です。"))
    end)

    it("treats full-width ! and ? as sentence ends", function()
      assert.are.same({ 12, 24 }, sentence.ends("本当か？そうだ！"))
    end)

    it("includes trailing closing brackets in the sentence end", function()
      -- 「(3) 終(6) わ(9) り(12) 。(15) 」(18) 次(21)。(24)
      assert.are.same({ 18, 24 }, sentence.ends("「終わり。」次。"))
    end)

    it("merges the ideographic ellipsis run into one end", function()
      assert.are.same({ 15 }, sentence.ends("なんと……"))
    end)

    it("does not treat the comma as a sentence end", function()
      assert.are.same({}, sentence.ends("これ、それ"))
    end)
  end)

  describe("ends() with indirect quotes (bunkai-style exception)", function()
    it("does not end inside a quoted sentence followed by と言った", function()
      -- 内側の 。」は文末ではない。外側の文末 (最後の 。) だけが残る
      local line = "彼は「そうだ。」と言った。"
      assert.are.same({ #line }, sentence.ends(line))
    end)

    it("does not end inside a quoted noun phrase followed by という", function()
      local line = "「はい」という答え。"
      assert.are.same({ #line }, sentence.ends(line))
    end)

    it("keeps boundaries when the quote is not a quote-phrase", function()
      -- 「終わり。」次。 は普通に 2 文末
      assert.are.same({ 18, 24 }, sentence.ends("「終わり。」次。"))
    end)

    it("suppresses the inner boundary for quoted object phrases too", function()
      -- 「はい。」をください。 → 「はい。」は目的語の引用句なので、
      -- 文末は最後の 。 のみ (bunkai より積極的: を/は/が/も/で も接続扱い)
      local line = "「はい。」をください。"
      assert.are.same({ #line }, sentence.ends(line))
    end)

    it("does not suppress boundaries without a closing bracket", function()
      -- bunkai は「。と…」も抑制するが、移動用途では抑制しない (意図的な差異)
      local line = "今日は晴れ。とにかく出かけた。"
      assert.are.same({ 18, #line }, sentence.ends(line))
    end)
  end)

  describe("ends() with a period before closing quotes (english)", function()
    it("ends after the closing quote when followed by whitespace", function()
      local line = 'He said "Stop." Then we left.'
      -- Stop." の " (15 バイト目) と文末
      assert.are.same({ 15, #line }, sentence.ends(line))
    end)
  end)

  describe("ends() for english text", function()
    it("finds sentence ends followed by whitespace or line end", function()
      -- "Hello world. " = 13 bytes (.) at 12, "How are you?" = 12 bytes
      assert.are.same({ 12, 25 }, sentence.ends("Hello world. How are you?"))
    end)

    it("does not treat decimals as sentence ends", function()
      assert.are.same({ 11 }, sentence.ends("3.14 is pi."))
    end)

    it("does not treat abbreviations as sentence ends", function()
      assert.are.same({ 13 }, sentence.ends("U.S.A is big."))
    end)

    it("collapses an ascii ellipsis into one end", function()
      assert.are.same({ 7 }, sentence.ends("Wait..."))
    end)

    it("treats standalone ! and ? as ends", function()
      assert.are.same({ 5, 8 }, sentence.ends("Stop!Go?"))
    end)
  end)

  describe("ends() for mixed text", function()
    it("applies each rule per candidate", function()
      local line = "Vimはエディタだ。It works."
      -- Vimはエディタだ。 = 24 bytes、It works. がそこに続く (計 33 bytes)
      assert.are.same({ 24, 33 }, sentence.ends(line))
    end)

    it("returns an empty table for empty lines", function()
      assert.are.same({}, sentence.ends(""))
    end)
  end)
end)

describe("bunsetsu._commands.sentence (sentence motion)", function()
  local sentence_motion = require("bunsetsu._commands.sentence")
  local util = require("bunsetsu._core.util")

  before_each(function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "一文目です。二文目です。",
      "三文目です。",
    })
  end)

  it("next_end() moves to the sentence end on the same line", function()
    util.set_cursor(1, 1)
    assert.is_true(sentence_motion.next_end(1))
    assert.are.same({ 1, 17 }, util.get_cursor()) -- 「一文目です。」の 。 (18 の 0始まり)
  end)

  it("next_end() crosses lines", function()
    util.set_cursor(1, 1)
    sentence_motion.next_end(3)
    assert.are.same({ 2, 17 }, util.get_cursor())
  end)

  it("next_end() supports counts", function()
    util.set_cursor(1, 1)
    sentence_motion.next_end(2)
    assert.are.same({ 1, 35 }, util.get_cursor()) -- 二文目です。の末尾
  end)

  it("next_end() skips the sentence end under the cursor", function()
    util.set_cursor(1, 18)
    assert.is_true(sentence_motion.next_end(1))
    assert.are.same({ 1, 35 }, util.get_cursor())
  end)

  it("next_end() returns false and keeps the cursor when no end remains", function()
    util.set_cursor(2, 18)
    assert.is_false(sentence_motion.next_end(1))
    assert.are.same({ 2, 17 }, util.get_cursor())
  end)

  it("prev_end() moves to the previous sentence end", function()
    util.set_cursor(2, 1)
    assert.is_true(sentence_motion.prev_end(1))
    assert.are.same({ 1, 35 }, util.get_cursor())
  end)

  it("prev_end() skips the sentence end under the cursor", function()
    util.set_cursor(1, 36)
    assert.is_true(sentence_motion.prev_end(1))
    assert.are.same({ 1, 17 }, util.get_cursor())
  end)

  it("prev_end() returns false at the first sentence end", function()
    util.set_cursor(1, 18)
    assert.is_false(sentence_motion.prev_end(1))
  end)

  it("works on english text", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "One. Two. Three." })
    util.set_cursor(1, 1)
    sentence_motion.next_end(1)
    assert.are.same({ 1, 3 }, util.get_cursor())
    sentence_motion.next_end(1)
    assert.are.same({ 1, 8 }, util.get_cursor())
  end)
end)
