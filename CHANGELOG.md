# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
