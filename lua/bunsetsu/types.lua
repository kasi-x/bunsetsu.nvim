--- LuaCATS 型定義 (mini.doc 用のコメント形式も併記)
---
--- `luals` はここで定義した型をグローバルに使う。

---@class Bunsetsu.Vibrato
---@field cmd string Vibrato tokenize CLI のパス
---@field dict string MeCab 形式辞書のパス

---@class Bunsetsu.Vaporetto
---@field cmd string Vaporetto predict CLI のパス
---@field model string Vaporetto モデルファイルのパス (.model.zst)

---@class Bunsetsu.Lemma
---@field dict_path string UniDic TSV (surface<TAB>lemma<TAB>reading<TAB>pos) のパス

---@class Bunsetsu.Highlight
---@field enabled boolean 品詞ごとのアンダーライン表示を有効にするか

---@class Bunsetsu.Config
---@field model string 同梱モデル名 (knbc_bunsetu / wpci_bunsetu / jeita / rwcp)。
---Vibrato 未設定時に使われる
---@field splitpat string 強制区切り文字のパターン。シンプルな文字クラス
---'[...]' のみ解釈する (例: "[?!、。]")。空文字列で無効化
---@field splitsep string :BunsetsuSplit の区切り文字列
---@field debounce number 全文キャッシュ無効化のデバウンス(ms)
---@field vibrato? Bunsetsu.Vibrato Vibrato バックエンド設定
---@field vaporetto? Bunsetsu.Vaporetto Vaporetto バックエンド設定
---@field lemma? Bunsetsu.Lemma UniDic 辞書引き設定
---@field highlight? Bunsetsu.Highlight 品詞ハイライト設定

---@class SegmentCol
---@field segment string
---@field col number
---@field colend number

---@class FullSegment
---@field lnum number 行番号(1始まり)
---@field col number 開始列(バイト位置、1始まり)
---@field colend number 終了列(バイト位置、1始まり)
---@field idx number 行内のsegmentインデックス(1始まり)
---@field text string segment文字列
