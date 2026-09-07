describe("bunsetsu.lemma (UniDic lookup)", function()
  local lemma = require("bunsetsu._core.lemma")

  local tmp

  before_each(function()
    tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write(table.concat({
      "走っ\t走る\tハシル\t動詞",
      "実験\t実験\tジッケン\t名詞",
      "走っ\t走る\tハシッ\t動詞", -- 重複行は先勝り
      "", -- 空行はスキップ
      "壊れた行", -- 列数が合わない行はスキップ
    }, "\n"))
    f:close()
  end)

  after_each(function()
    os.remove(tmp)
    lemma.clear_cache()
  end)

  it("looks up lemma / reading / pos by surface", function()
    local entry = lemma.lookup("走っ", tmp)
    assert.is_not_nil(entry)
    assert.are.equal("走る", entry.lemma)
    assert.are.equal("ハシル", entry.reading)
    assert.are.equal("動詞", entry.pos)
  end)

  it("returns nil for unknown surfaces", function()
    assert.is_nil(lemma.lookup("こんな語は無い", tmp))
  end)

  it("returns nil for empty surface", function()
    assert.is_nil(lemma.lookup("", tmp))
  end)

  it("has() reports membership", function()
    assert.is_true(lemma.has("実験", tmp))
    assert.is_false(lemma.has("未知語", tmp))
  end)

  it("reloads the file after clear_cache()", function()
    assert.are.equal("ハシル", lemma.lookup("走っ", tmp).reading)
    -- ファイルの該当行を書き換える
    local f = io.open(tmp, "w")
    f:write("走っ\t走る\tハシッ\t動詞\n")
    f:close()
    -- キャッシュが効いている間は古い値
    assert.are.equal("ハシル", lemma.lookup("走っ", tmp).reading)
    lemma.clear_cache()
    assert.are.equal("ハシッ", lemma.lookup("走っ", tmp).reading)
  end)

  it("treats unreadable dictionary as empty (no error)", function()
    assert.is_nil(lemma.lookup("走っ", "/nonexistent/path/unidic.tsv"))
  end)

  it("treats malformed lines as missing entries", function()
    assert.is_nil(lemma.lookup("壊れた行", tmp))
  end)
end)
