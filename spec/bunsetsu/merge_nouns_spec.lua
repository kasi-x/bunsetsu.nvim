describe("merge_nouns option (compound noun detection)", function()
  local segment = require("bunsetsu._core.segment")
  local config = require("bunsetsu._core.configuration")
  local vibrato = require("bunsetsu._commands.vibrato")

  local words = { "形態素", "解析", "を", "東京", "大学", "で", "学ぶ" }
  local positions = { 1, 10, 16, 19, 25, 31, 37 }
  local infos = {
    { pos = "名詞" },
    { pos = "名詞" },
    { pos = "助詞" },
    { pos = "名詞" },
    { pos = "名詞" },
    { pos = "助詞" },
    { pos = "動詞" },
  }

  before_each(function()
    config.initialize_data_if_needed()
    config.resolve_data()
    vibrato.tokenize_detailed = function(line)
      return words, infos
    end
  end)

  after_each(function()
    config.resolve_data({ merge_nouns = false })
  end)

  it("does not merge nouns by default", function()
    config.resolve_data({ merge_nouns = false })
    local segcols = segment.words_to_segments(words, positions, infos)
    local texts = vim.tbl_map(function(sc)
      return sc.segment
    end, segcols)
    assert.are.same({
      "形態素",
      "解析を",
      "東京",
      "大学で",
      "学ぶ",
    }, texts)
  end)

  it("merges consecutive nouns when merge_nouns is enabled", function()
    config.resolve_data({ merge_nouns = true })
    local segcols = segment.words_to_segments(words, positions, infos)
    local texts = vim.tbl_map(function(sc)
      return sc.segment
    end, segcols)
    assert.are.same({
      "形態素解析を",
      "東京大学で",
      "学ぶ",
    }, texts)
  end)

  it("still respects particle merging with merge_nouns enabled", function()
    config.resolve_data({ merge_nouns = true })
    local segcols = segment.words_to_segments(words, positions, infos)
    -- 「を」「で」は助詞なので前の segment に結合される
    assert.is_truthy(segcols[1].segment:find("を$"))
    assert.is_truthy(segcols[2].segment:find("で$"))
  end)

  it("works with words_to_segments infos = nil (merge_nouns inactive)", function()
    config.resolve_data({ merge_nouns = true })
    local segcols = segment.words_to_segments(words, positions, nil)
    -- infos がないので品詞判定できず、名詞結合は発動しない
    assert.are.equal(7, #segcols)
  end)
end)
