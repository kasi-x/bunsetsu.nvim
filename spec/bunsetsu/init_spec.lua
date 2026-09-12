describe("bunsetsu (public API)", function()
  local bunsetsu = require("bunsetsu")
  local config = require("bunsetsu._core.configuration")
  local full = require("bunsetsu._commands.full")
  local spider = require("bunsetsu._commands.spider")

  before_each(function()
    config.initialize_data_if_needed()
    config.resolve_data()
    full.invalidate()
  end)

  after_each(function()
    config.resolve_data({
      splitpat = "[?!、。]",
      splitsep = " ",
      vibrato = { dict = "" },
      vaporetto = { model = "" },
    })
    vim.g.bunsetsu_configuration = nil
  end)

  describe("split_lines() (:BunsetsuSplit)", function()
    it("splits the line with the TinySegmenter backend", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
      bunsetsu.split_lines(1, 1)
      assert.are.same({ "これは 文章です。" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("joins segments with the configured splitsep", function()
      config.resolve_data({ splitsep = "|" })
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
      bunsetsu.split_lines(1, 1)
      assert.are.same({ "これは|文章です。" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("uses the Vibrato backend when a dictionary is configured", function()
      config.resolve_data({ vibrato = { dict = "/tmp/fake.dic" } })
      local vibrato = require("bunsetsu._commands.vibrato")
      local original = vibrato.tokenize_detailed
      vibrato.tokenize_detailed = function(line)
        if line == "これは文章です。" then
          return { "これ", "は", "文章", "です", "。" }, {
            { pos = "名詞" },
            { pos = "助詞" },
            { pos = "名詞" },
            { pos = "助動詞" },
            { pos = "記号" },
          }
        end
        return {}, {}
      end

      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
      bunsetsu.split_lines(1, 1)
      vibrato.tokenize_detailed = original
      -- 助詞・助動詞・句読点は前の語に結合される
      assert.are.same({ "これは 文章です。" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)
  end)

  describe("models()", function()
    it("always reports the bundled TinySegmenter", function()
      assert.are.same({ "tinysegmenter" }, bunsetsu.models())
    end)

    it("reports external backends when configured", function()
      config.resolve_data({
        vibrato = { dict = "/tmp/fake.dic" },
        vaporetto = { model = "/tmp/fake.model" },
      })
      assert.are.same({ "tinysegmenter", "vibrato", "vaporetto" }, bunsetsu.models())
    end)
  end)

  describe("pattern() backend dispatch", function()
    it("uses the TinySegmenter pattern by default", function()
      assert.are.equal(spider.pattern, bunsetsu.pattern("bunsetsu"))
    end)

    it("prefers Vibrato when a dictionary is configured", function()
      config.resolve_data({ vibrato = { dict = "/tmp/fake.dic" } })
      assert.are_not.equal(spider.pattern, bunsetsu.pattern("bunsetsu"))
    end)

    it("falls back to Vaporetto when only a model is configured", function()
      config.resolve_data({ vaporetto = { model = "/tmp/fake.model" } })
      assert.are_not.equal(spider.pattern, bunsetsu.pattern("bunsetsu"))
    end)
  end)

  describe("lemma_under_cursor()", function()
    it("uses cword for ascii text", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
      vim.api.nvim_win_set_cursor(0, { 1, 7 }) -- "world" の上
      local r = bunsetsu.lemma_under_cursor()
      assert.is_not_nil(r)
      assert.are.equal("world", r.surface)
      assert.are.equal("world", r.lemma)
      assert.are.equal("", r.pos)
    end)

    it("returns vibrato info for the token under the cursor", function()
      config.resolve_data({ vibrato = { dict = "/tmp/fake.dic" } })
      local vibrato = require("bunsetsu._commands.vibrato")
      local original = vibrato.tokenize_detailed
      vibrato.tokenize_detailed = function(line)
        if line == "これは走った。" then
          return { "これ", "は", "走っ", "た", "。" }, {
            { pos = "名詞", lemma = "", reading = "" },
            { pos = "助詞", lemma = "", reading = "" },
            { pos = "動詞", lemma = "走る", reading = "ハシル" },
            { pos = "助動詞", lemma = "", reading = "" },
            { pos = "記号", lemma = "", reading = "" },
          }
        end
        return {}, {}
      end

      -- 「走っ」はバイト位置 10-15
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは走った。" })
      vim.api.nvim_win_set_cursor(0, { 1, 11 })
      local r = bunsetsu.lemma_under_cursor()
      vibrato.tokenize_detailed = original
      assert.is_not_nil(r)
      assert.are.equal("走っ", r.surface)
      assert.are.equal("走る", r.lemma)
      assert.are.equal("ハシル", r.reading)
      assert.are.equal("動詞", r.pos)
    end)

    it("falls back to the bundled TinySegmenter when Vibrato is not configured", function()
      config.resolve_data({ vibrato = { dict = "" } })
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
      vim.api.nvim_win_set_cursor(0, { 1, 11 }) -- 「文章です。」の中 (byte 12)
      local r = bunsetsu.lemma_under_cursor()
      assert.is_not_nil(r)
      -- 表層形のみ取得できる (品詞・読みは空)
      assert.are.equal("文章です。", r.surface)
      assert.are.equal("文章です。", r.lemma)
      assert.are.equal("", r.reading)
      assert.are.equal("", r.pos)
    end)

    it("returns nil on an empty line", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      assert.is_nil(bunsetsu.lemma_under_cursor())
    end)
  end)
end)
