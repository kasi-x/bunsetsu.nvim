--- All functions and data to help customize `bunsetsu` for this user.
---
--- オプションは目的別に 3 つの層に分かれる。
---   1. 基本 — バックエンドの選択と見た目。ほとんどのユーザーはここだけ。
---   2. 調整 — 性能・外部連携の微調整。
---   3. 仕様 — 「文節」「文」の区切り規則そのものを変える。
---
--- 詳細は README の Configuration と doc/bunsetsu.txt の *bunsetsu-config*。

---@class Bunsetsu.Config.Vibrato
---@field cmd string tokenize CLI のパス。既定 "vibrato"
---@field dict string 辞書 (.dic.zst) のパス。空なら Vibrato 無効 (既定)
---@field auto_setup boolean true で自動セットアップを有効化。CLI の
---   cargo ビルドと辞書のダウンロードを stdpath("data")/bunsetsu/vibrato
---   配下へ行い、cmd / dict をその導入へ差し替える。未導入なら setup() の
---   auto_setup_delay ms 後にバックグラウンドで実行し、完了までの間は
---   TinySegmenter で動作する
---@field auto_setup_delay number 自動セットアップの開始を遅らせる時間
---   (ms)。起動直後の I/O と競合しないよう、既定では 3 秒待つ。既定 3000
---@field pos boolean 品詞・原形・読みの抽出。false で高速化
---   (highlight / lemma は使えなくなる)。既定 true
---@field flavor string 自動セットアップ (auto_setup = true) の辞書の種類。
---   "ipadic" (既定) / "unidic-mecab" / "unidic-cwj" / "jumandic" /
---   "naist-jdic"
---@field version string 自動セットアップでビルドする vibrato のタグ。
---   既定 "v0.5.2"

---@class Bunsetsu.Config.Vaporetto
---@field cmd string predict CLI のパス。既定 "predict"
---@field model string モデル (.model.zst) のパス。空なら Vaporetto 無効 (既定)

---@class Bunsetsu.Config.Lemma
---@field dict_path string UniDic TSV (surface<TAB>lemma<TAB>reading<TAB>pos)。
---   空なら辞書引き無効 (既定)

---@class Bunsetsu.Config.Highlight
---@field enabled boolean 品詞ハイライトの有効化。既定 false

---@class Bunsetsu.Config.Sentence
---@field extra_end_chars string 既定の文末文字 (。！？…．｡) に追加する文末
---   文字。既定 ""

---@class Bunsetsu.Config
-- == 基本: バックエンドと見た目 ==
-- 同梱 TinySegmenter の文節モデル ("knbc_bunsetu" / "wpci_bunsetu" /
-- "jeita" / "rwcp")。vibrato / vaporetto 未設定時のみ使われる。
---@field model string
-- 品詞ごとのアンダーライン表示。
---@field highlight Bunsetsu.Config.Highlight
-- == 調整: 性能・外部連携 ==
-- Vibrato バックエンド (dict を設定すると有効化)。
---@field vibrato Bunsetsu.Config.Vibrato
-- Vaporetto バックエンド (model を設定すると有効化)。
---@field vaporetto Bunsetsu.Config.Vaporetto
-- UniDic 辞書引き。
---@field lemma Bunsetsu.Config.Lemma
-- 全文キャッシュ無効化のデバウンス (ms)。
---@field debounce number
-- 日本語検出でバッファ先頭から走査する行数。
---@field jp_scan_lines number
-- == 仕様: 区切りの規則 ==
-- 強制的に分節区切りを入れる文字のパターン ('[...]' の文字クラスのみ)。
---@field splitpat string
-- :BunsetsuSplit が挿入する区切り文字列。
---@field splitsep string
-- 連続する名詞を一つの文節にまとめる (Vibrato / Vaporetto 使用時)。
---@field merge_nouns boolean
-- 文末判定の追加設定。
---@field sentence Bunsetsu.Config.Sentence

local M = {}

-- NOTE: Don't remove this line. It makes the Lua module much easier to reload
vim.g.loaded_bunsetsu = false

---@type Bunsetsu.Config
M.DATA = {}

---@type Bunsetsu.Config
local _DEFAULTS = {
  model = "knbc_bunsetu",
  splitpat = "[?!、。]",
  splitsep = " ",
  debounce = 50,
  vibrato = {
    cmd = "vibrato",
    dict = "",
    -- 品詞・原形・読みの抽出を有効化 (highlight / lemma に必要)。
    -- false で高速化 (文節移動には影響しない)
    pos = true,
    -- true で自動セットアップ: tokenize CLI を cargo でビルドし、辞書を
    -- stdpath("data")/bunsetsu/vibrato 配下へ導入して cmd / dict を差し替える。
    -- 未導入なら setup() の auto_setup_delay ms 後にバックグラウンドで実行する
    auto_setup = false,
    -- 自動セットアップの開始を遅らせる時間 (ms)。起動直後の I/O 競合を避ける
    auto_setup_delay = 3000,
    -- 自動セットアップの辞書の種類とビルド元タグ
    flavor = "ipadic",
    version = "v0.5.2",
  },
  vaporetto = {
    cmd = "predict",
    model = "",
  },
  lemma = {
    -- UniDic TSV (surface<TAB>lemma<TAB>reading<TAB>pos)。
    -- lex_3_1.csv から `bunsetsu.tools` のスクリプトで生成する。
    dict_path = "",
  },
  highlight = {
    -- 品詞ごとにアンダーラインで色を付ける。
    enabled = false,
  },
  -- 文末移動の追加設定
  sentence = {
    -- 既定の文末文字 (。！？…．｡) に追加する文末文字
    extra_end_chars = "",
  },
  -- 連続する名詞を一つの文節にまとめる (Vibrato/Vaporetto のみ)
  -- 例: 形態素(名詞)+解析(名詞) → 形態素解析
  merge_nouns = false,
  -- 日本語検出の走査行数 (バッファ先頭からこの行数を走査して
  -- 日本語を含むかを判定する)
  jp_scan_lines = 500,
}

--- Setup `bunsetsu` for the first time, if needed.
function M.initialize_data_if_needed()
  if vim.g.loaded_bunsetsu then
    return
  end

  M.DATA = vim.tbl_deep_extend("force", _DEFAULTS, vim.g.bunsetsu_configuration or {})

  vim.g.loaded_bunsetsu = true
end

--- Merge `data` with the user's current configuration.
---
---`vim.g.bunsetsu_configuration` はプラグイン読み込み順によっては
---`initialize_data_if_needed` の後に設定されることがあるため、ここで常に
---マージしてから data を適用する。
---
---@param data? Bunsetsu.Config All extra customizations for this plugin.
---@return Bunsetsu.Config # The configuration with 100% filled out values.
function M.resolve_data(data)
  M.initialize_data_if_needed()

  -- 後から設定された vim.g.bunsetsu_configuration を必ず反映する
  M.DATA = vim.tbl_deep_extend("force", M.DATA, vim.g.bunsetsu_configuration or {})
  M.DATA = vim.tbl_deep_extend("force", M.DATA, data or {})

  M.resolve_vibrato_managed()

  return M.DATA
end

---vibrato.auto_setup の解決。
---管理導入 (stdpath("data") 配下) の manifest があれば cmd / dict を
---そのパスへ差し替える。無い場合はバックエンドを無効化してセットアップ
---待ちフラグを立てる (lifecycle.setup が自動実行する)。
---auto_setup が false なら何もしない (cmd / dict はユーザー指定どおり)。
function M.resolve_vibrato_managed()
  local v = M.DATA.vibrato
  if not v or not v.auto_setup then
    M._vibrato_auto_pending = false
    return
  end
  local manifest = require("bunsetsu._commands.vibrato_setup").read_manifest()
  if manifest then
    v.cmd, v.dict = manifest.cmd, manifest.dict
    M._vibrato_auto_pending = false
  else
    v.cmd, v.dict = "", ""
    M._vibrato_auto_pending = true
  end
end

---自動セットアップがまだ行われていないか (フラグを消費する)。
---@return boolean
function M.consume_auto_setup_needed()
  local pending = M._vibrato_auto_pending
  M._vibrato_auto_pending = false
  return pending == true
end

---自動セットアップ完了時に manifest のパスを設定へ反映する。
---(lifecycle.setup の自動実行と bunsetsu.vibrato_setup() の共通処理)
---@param manifest Bunsetsu.VibratoManifest
function M.apply_vibrato_manifest(manifest)
  M.DATA.vibrato.cmd = manifest.cmd
  M.DATA.vibrato.dict = manifest.dict
  require("bunsetsu._commands.full").invalidate()
  vim.notify(
    "bunsetsu: Vibrato のセットアップが完了しました ("
      .. manifest.version
      .. " / "
      .. manifest.flavor
      .. ")。バックエンドを切り替えました",
    vim.log.levels.INFO,
    { title = "bunsetsu.nvim" }
  )
end

---外部トークナイザ (Vibrato) を使うかどうか。辞書未設定なら TinySegmenter。
---@return boolean
function M.use_vibrato()
  local dict = M.DATA.vibrato and M.DATA.vibrato.dict or ""
  return dict ~= ""
end

---現在有効なバックエンドのキャッシュキーを返す。
---(use_vibrato / vaporetto.model / 同梱モデル名の順で判定)
---@return string
function M.current_model()
  if M.use_vibrato() then
    return M.DATA.vibrato.dict
  end
  local vm = M.DATA.vaporetto and M.DATA.vaporetto.model or ""
  if vm ~= "" then
    return vm
  end
  return M.DATA.model
end

return M
