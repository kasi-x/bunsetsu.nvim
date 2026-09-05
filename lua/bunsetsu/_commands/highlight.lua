---形態素 (品詞) の色分け表示。
---
---Vibrato で分割した各語の品詞に応じて、アンダーラインで色を付ける。
---nvim_buf_set_extmark を使い、バッファの日本語部分だけを対象にする。

local M = {}

---品詞大分類 → ハイライトグループのマッピング。
---各グループは init 時に定義される。
local POS_HL = {
  ["動詞"] = "BunsetsuVerb",
  ["名詞"] = "BunsetsuNoun",
  ["形容詞"] = "BunsetsuAdjective",
  ["形容動詞"] = "BunsetsuAdjective",
  ["副詞"] = "BunsetsuAdverb",
  ["助詞"] = "BunsetsuParticle",
  ["助動詞"] = "BunsetsuParticle",
  ["感動詞"] = "BunsetsuInterjection",
  ["連体詞"] = "BunsetsuAdnominal",
  ["接続詞"] = "BunsetsuConjunction",
  ["記号"] = "BunsetsuSymbol",
}

---ハイライトグループを定義する (初回のみ)。
local hl_defined = false

---@return boolean
local function define_highlights()
  if hl_defined then
    return true
  end
  local groups = {
    BunsetsuVerb = { gui = "underline", guifg = "#f07178", ctermfg = 1 },
    BunsetsuNoun = { gui = "underline", guifg = "#82aaff", ctermfg = 4 },
    BunsetsuAdjective = { gui = "underline", guifg = "#c3e88d", ctermfg = 2 },
    BunsetsuAdverb = { gui = "underline", guifg = "#ffcb6b", ctermfg = 3 },
    BunsetsuParticle = { gui = "underline", guifg = "#546e7a", ctermfg = 8 },
    BunsetsuInterjection = { gui = "underline", guifg = "#ff9e64", ctermfg = 5 },
    BunsetsuAdnominal = { gui = "underline", guifg = "#b39ddb", ctermfg = 6 },
    BunsetsuConjunction = { gui = "underline", guifg = "#89ddff", ctermfg = 14 },
    BunsetsuSymbol = { gui = "underline", guifg = "#8c8c8c", ctermfg = 7 },
  }
  for name, opts in pairs(groups) do
    pcall(vim.api.nvim_set_hl, 0, name, opts)
  end
  hl_defined = true
  return true
end

---品詞大分類を取得する ("動詞,自立,..." → "動詞")。
---@param pos string
---@return string
local function pos_big(pos)
  if not pos or pos == "" then
    return ""
  end
  return vim.split(pos, ",", { plain = true })[1]
end

---バッファの日本語を分割し、品詞ごとにアンダーラインの extmark を付ける。
---既存の bunsetsu extmark は namespace 単位で削除してから再設定する。
---@param buf number バッファ番号
---@param namespace number extmark namespace
function M.apply(buf, namespace)
  define_highlights()
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local vibrato = require("bunsetsu._commands.vibrato")

  -- 日本語を含む行だけを処理
  local tasks = {}
  for lnum, line in ipairs(lines) do
    if line:match("[ぁ-んァ-ヶー一-龠]") then
      tasks[#tasks + 1] = { lnum = lnum, line = line }
    end
  end
  if #tasks == 0 then
    return
  end

  -- 非同期で分割し、結果を extmark に反映する
  vibrato.tokenize_async(tasks, function(results)
    for _, r in ipairs(results) do
      local lnum = r.lnum
      local search_from = 1
      for i, word in ipairs(r.words) do
        local pos = r.infos[i] and r.infos[i].pos or ""
        local hl = POS_HL[pos_big(pos)]
        if hl then
          local found = vim.fn.stridx(r.line, word, search_from - 1) + 1
          if found <= 0 then
            found = search_from
          end
          local col_start = found - 1 -- extmark は 0-based byte
          local col_end = col_start + #word
          pcall(vim.api.nvim_buf_set_extmark, buf, namespace, lnum - 1, col_start, {
            end_col = col_end,
            hl_group = hl,
            hl_mode = "combine",
          })
          search_from = found + #word
        end
      end
    end
  end)
end

return M
