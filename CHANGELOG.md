# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- TinySegmenter の Lua 移植 (`lua/bunsetsu/_core/tinysegmenter.lua`)
- 文節区切りモデル 4 種: knbc_bunsetu / wpci_bunsetu / jeita / rwcp
- nvim-spider 拡張: カーソル下が日本語なら文節移動・ASCII なら spider に委譲
- flash.nvim 拡張: 事前計算した文節一覧を matcher に渡しラベルジャンプ
- 一文モード (カーソル行のみ即時分割) と全文モード (バッファ全体を事前分割、
  編集時は変更行のみ再計算)
- `:BunsetsuSplit` コマンド
- `:checkhealth bunsetsu`

### Added (base)

- [nvim-best-practices-plugin-template](https://github.com/ColinKennedy/nvim-best-practices-plugin-template)
  の構造・テスト作法を採用
