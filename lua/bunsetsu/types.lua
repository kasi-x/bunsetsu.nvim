--- LuaCATS 型定義 (mini.doc 用のコメント形式も併記)
---
--- `luals` はここで定義した型をグローバルに使う。

---@class Bunsetsu.Vaporetto
---@field cmd string Vaporetto predict CLI のパス
---@field model string Vaporetto モデルファイルのパス (.model.zst)

---@class Bunsetsu.Config
---@field model string 文節区切りモデル名 (knbc_bunsetu / wpci_bunsetu / jeita / rwcp)
---@field splitpat string 強制的に分節区切りを入れるパターン
---@field splitsep string :BunsetsuSplit の区切り文字列
---@field debounce number 全文キャッシュ無効化のデバウンス(ms)
---@field vaporetto? Bunsetsu.Vaporetto Vaporetto バックエンド設定

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
