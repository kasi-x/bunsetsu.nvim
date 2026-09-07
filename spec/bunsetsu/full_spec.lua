describe("bunsetsu.full (full-text mode with incremental cache)", function()
  local full = require("bunsetsu._commands.full")
  local segment = require("bunsetsu._core.segment")

  before_each(function()
    full.invalidate()
    segment.clear_cache()
  end)

  it("computes full segments for the whole buffer", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "これは文章です。",
      "Vimはエディタです。",
    })
    local segs = full.full("knbc_bunsetu")
    assert.are.same(4, #segs)
    assert.are.same(1, segs[1].lnum)
    assert.are.same("これは", segs[1].text)
    assert.are.same(2, segs[3].lnum)
    assert.are.same("Vimは", segs[3].text)
  end)

  it("reuses cache when the line is unchanged", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
    local segs1 = full.full("knbc_bunsetu")
    -- キャッシュから同一オブジェクトが返る
    local segs2 = full.full("knbc_bunsetu")
    assert.are.same(segs1, segs2)
  end)

  it("invalidates only the changed line", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "これは文章です。",
      "すもももももももものうち",
    })
    local before = full.full("knbc_bunsetu")
    -- 1行目「これは文章です。」=2分割, 2行目「すもも…」=2分割 => 4
    assert.are.same(4, #before)
    -- 2行目を変更
    vim.api.nvim_buf_set_lines(0, 1, 2, false, { "日本語の文章です。" })
    full.invalidate(2)
    local after = full.full("knbc_bunsetu")
    -- 1行目は変わっていない
    assert.are.same("これは", after[1].text)
    assert.are.same(1, after[1].lnum)
    -- 2行目が新しい内容になる
    local l2 = {}
    for _, fs in ipairs(after) do
      if fs.lnum == 2 then
        l2[#l2 + 1] = fs.text
      end
    end
    assert.are.same({ "日本語の", "文章です。" }, l2)
  end)

  it("invalidate() without arg clears everything", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
    full.full("knbc_bunsetu")
    full.invalidate()
    local segs = full.full("knbc_bunsetu")
    assert.are.same(2, #segs)
  end)

  it("next() returns segment after cursor", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local nxt = full.next("knbc_bunsetu")
    assert.is_not_nil(nxt)
    assert.are.same("文章です。", nxt.text)
    assert.are.same(10, nxt.col)
  end)

  it("prev() returns the segment containing the cursor", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
    -- カーソルを「文章です。」(col10-24)の内部 col12 に置く
    vim.api.nvim_win_set_cursor(0, { 1, 11 })
    local prv = full.prev("knbc_bunsetu")
    assert.is_not_nil(prv)
    assert.are.same("文章です。", prv.text)
  end)

  it("prev() returns the previous segment when cursor is at segment start", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
    -- カーソルを「文章です。」(col10-24)の先頭 col10 に置く
    vim.api.nvim_win_set_cursor(0, { 1, 9 })
    local prv = full.prev("knbc_bunsetu")
    assert.is_not_nil(prv)
    assert.are.same("文章です。", prv.text)
  end)

  describe("with the Vibrato backend (stubbed tokenizer)", function()
    local config = require("bunsetsu._core.configuration")
    local vibrato = require("bunsetsu._commands.vibrato")
    local original_tokenize_detailed
    local original_tokenize_async

    before_each(function()
      config.resolve_data({ vibrato = { dict = "/tmp/fake.dic" } })
      full.invalidate()
      original_tokenize_detailed = vibrato.tokenize_detailed
      original_tokenize_async = vibrato.tokenize_async
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
      vibrato.tokenize_async = function(lines, on_done)
        local results = {}
        for _, item in ipairs(lines) do
          local words, infos = vibrato.tokenize_detailed(item.line)
          results[#results + 1] = {
            lnum = item.lnum,
            line = item.line,
            words = words,
            positions = segment.word_positions(item.line, words),
            infos = infos,
          }
        end
        on_done(results)
      end
    end)

    after_each(function()
      vibrato.tokenize_detailed = original_tokenize_detailed
      vibrato.tokenize_async = original_tokenize_async
      config.resolve_data({ vibrato = { dict = "" } })
      full.invalidate()
    end)

    it("merges particles and keeps punctuation with the previous segment", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
      local segs = full.full("knbc_bunsetu")
      assert.are.same(
        { "これは", "文章です。" },
        vim.tbl_map(function(fs)
          return fs.text
        end, segs)
      )
      assert.are.same(1, segs[1].col)
      assert.are.same(24, segs[2].colend)
    end)

    it("preload() caches async results", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
      full.preload("knbc_bunsetu")
      -- preload は linecache を埋め、full() はそれを使って組み立てる
      local segs = full.full("knbc_bunsetu")
      assert.are.same(
        { "これは", "文章です。" },
        vim.tbl_map(function(fs)
          return fs.text
        end, segs)
      )
    end)

    it("refresh_line() re-segments only the given line", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
      full.refresh_line("knbc_bunsetu", 1)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "すもももももももものうち" })
      full.refresh_line("knbc_bunsetu", 1)
      -- スタブは未知の行を空で返すので segment は 0 個になる
      local segs = full.full("knbc_bunsetu")
      assert.are.same(0, #segs)
    end)
  end)
end)
