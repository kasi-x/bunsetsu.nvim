--- UniDic 辞書引きによる原形(辞書形)・読み・品詞の取得。
---
--- 入力: `surface<TAB>lemma<TAB>reading<TAB>pos` の TSV (lex_3_1.csv から生成)。
--- メモリ上にハッシュテーブルとして保持し、Vaporetto で分割した語を引く。
---
--- pos 列は UniDic の大分類 (動詞/名詞/形容詞/助動詞...) で、Vaporetto の
--- predict-tags 出力 (動詞-一般, 名詞-普通名詞-サ変可能) の先頭部と一致する。

local M = {}

---@type table<string, { lemma: string, reading: string, pos: string }> | nil
local cached = nil

---UniDic TSV を読み込む。初回のみファイルから読む。
---@param path string TSV ファイルパス
---@return table<string, { lemma: string, reading: string, pos: string }>
local function load(path)
  if cached then
    return cached
  end
  cached = {}
  local lines = vim.fn.readfile(path)
  for _, line in ipairs(lines) do
    local parts = vim.split(line, "\t", { plain = true })
    if #parts == 4 then
      local surface, lemma, reading, pos = parts[1], parts[2], parts[3], parts[4]
      if surface ~= "" and not cached[surface] then
        cached[surface] = { lemma = lemma, reading = reading, pos = pos }
      end
    end
  end
  return cached
end

---マッピングをメモリから解放して再読み込みする。
function M.clear_cache()
  cached = nil
end

---指定語の辞書形・読み・品詞を返す。
---@param surface string 表層形 (Vaporetto の分割結果の語)
---@param path string UniDic TSV ファイルパス
---@return { lemma: string, reading: string, pos: string } | nil
function M.lookup(surface, path)
  if surface == "" then
    return nil
  end
  local dict = load(path)
  return dict[surface]
end

---指定語が辞書に載っているか。
---@param surface string
---@param path string
---@return boolean
function M.has(surface, path)
  return M.lookup(surface, path) ~= nil
end

return M
