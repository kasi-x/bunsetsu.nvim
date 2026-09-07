# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- 文末移動: `bunsetsu.next_sentence_end()` / `bunsetsu.prev_sentence_end()`。
  日本語の文末文字 (。！？…、直後の閉じ括弧も含む) と英語の文末記号
  (. ! ? は直後に空白・行末が続く場合のみ。"3.14" や "U.S.A" は誤検出しない)
  を判定し、混在文書でも文末ずつ移動できる
- 間接引用の例外 (fast-bunkai / bunkai の IndirectQuoteException を参考にした
  純 Lua 実装): 「〜だ。」と言った のように、閉じ括弧直後の文末が接続表現
  (と言った / という / は / が / を など) に続くときは内側を文末としない。
  外部の Rust/Python ランタイムは不要
- `_core.lang`: 日本語/英語判定モジュール
  (`has_japanese` / `jp_count` / `ascii_letter_count` / `script`)。
  プラグイン内の日本語判定をここに統一
- `bunsetsu.pattern([mode])`: spider 用カスタムパターン関数を返す。
  設定からバックエンドを自動選択する (vibrato 辞書 > vaporetto モデル >
  同梱 TinySegmenter)
- `bunsetsu.models()` が vaporetto も報告するようになった

### Fixed

- `splitpat` 設定が実際には無視されていた問題。シンプルな文字クラス
  (例: `"[?!、。]"`, `"[、]"`) を解釈し、解釈できないパターンは既定値に
  フォールバックする。`:BunsetsuSplit` と Vibrato バックエンドの全文モード
  にも splitpat が効くようになった
- UniDic 辞書ファイルが読めない場合に `bunsetsu.lemma()` がエラーではなく
  nil を返すようになった

### Changed

- 文節組み立てロジック (助詞結合・splitpat 強制区切り) を
  `bunsetsu._core.segment` に統合し、full / spider / :BunsetsuSplit 間の
  挙動を統一

## [1.0.0] - 2026-09-07

初回公開版。

### Added

- 文節 (bunsetsu) 単位の移動: nvim-spider 拡張 (カーソル下が日本語なら文節
  移動・ASCII なら spider に委譲) と flash.nvim 拡張 (文節へのラベルジャンプ)
- TinySegmenter の Lua 移植と文節区切りモデル 4 種 (knbc_bunsetu /
  wpci_bunsetu / jeita / rwcp) を同梱。追加バイナリなしでオフライン動作
- 高精度バックエンド (任意): Vibrato / Vaporetto CLI。単語分割に加えて
  品詞・原形・読みを取得
- `bunsetsu.lemma_under_cursor()` / `bunsetsu.lemma()`: カーソル下の語の
  辞書形・読み・品詞を取得
- 品詞ハイライト (`highlight.enabled` / `bunsetsu.highlight()`)
- 一文モード (カーソル行のみ即時分割) と全文モード (バッファ全体を事前分割、
  編集時は変更行のみ再計算)
- `:BunsetsuSplit` コマンド (分かち書き)
- `:checkhealth bunsetsu`

### Fixed

- lua-utf8 を真に任意依存に変更 (無い環境でもバイト単位フォールバックで動作)
- 日本語を含まないバッファでは TextChanged ごとの undo ツリー追跡
  (`undotree()`) をスキップし、コード編集時のオーバーヘッドを削減

### Added (base)

- [nvim-best-practices-plugin-template](https://github.com/ColinKennedy/nvim-best-practices-plugin-template)
  の構造・テスト作法を採用
