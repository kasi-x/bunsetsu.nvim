describe("bunsetsu configurable options", function()
  local sentence = require("bunsetsu._core.sentence")
  local config = require("bunsetsu._core.configuration")

  before_each(function()
    config.initialize_data_if_needed()
    config.resolve_data()
  end)

  after_each(function()
    config.resolve_data({
      sentence = { extra_end_chars = "" },
      jp_scan_lines = 500,
    })
  end)

  describe("sentence.extra_end_chars", function()
    it("adds custom sentence-ending characters", function()
      config.resolve_data({ sentence = { extra_end_chars = "♪" } })
      local ends = sentence.ends("素敵だ♪次へ進む")
      assert.are.equal(1, #ends)
      assert.are.equal(12, ends[1]) -- ♪ の末尾バイト
    end)

    it("does not add custom chars when empty", function()
      config.resolve_data({ sentence = { extra_end_chars = "" } })
      local ends = sentence.ends("素敵だ♪次へ進む")
      assert.are.equal(1, #ends)
    end)
  end)

  describe("jp_scan_lines", function()
    it("is configurable", function()
      config.resolve_data({ jp_scan_lines = 100 })
      assert.are.equal(100, config.DATA.jp_scan_lines)
    end)
  end)
end)
