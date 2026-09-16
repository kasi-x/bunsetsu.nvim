# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- テキストオブジェクト (is / as / iW / aW) が nvim-spider なしで動作するよう
  フォールバックを実装。spider があれば setEndpoints に委譲し、無ければ
  カーソル移動による直接選択 (operator-pending は v で一時 visual に入る手法)
- `_commands/motion.lua`: spider 非依存の文節移動モーション
  (`w` / `b` / `e` / `ge` 相当)。spider なしでも文節移動が可能に
- `bunsetsu.is_japanese_line()`: カーソル行の言語判定
  (自動切り替えキーマップの構築用)
- `merge_nouns` オプション: 連続する名詞を一つの segment にまとめる
  (Vibrato / Vaporetto 使用時。例: 形態素+解析 → 形態素解析)
- `sentence.extra_end_chars`: カスタム文末文字の追加
- `jp_scan_lines`: 日本語検出の走査行数設定
- `vibrato.pos`: 品詞抽出の有効/無効切り替え (既定 true)

### Changed

- `vibrato.pos` オプションを追加 (既定 true)。false で品詞抽出をスキップし
  文節移動を高速化 (highlight / lemma は使えなくなる)
- バックエンド選択ロジックを `_core.configuration` に統一
  (`configuration.use_vibrato()` / `configuration.current_model()`)
- `full.lua` の重複したバックエンド分岐を `full.line_segment_cols()` に統一

### Added

- `_core.tokenizer_engine`: Vibrato / Vaporetto 両バックエンドの常駐プロセス
  管理 (sync / async、pty の行分割、準備待ち、非同期バッチ) を一元化する
  共通エンジン。偽トークナイザを使った結合テストで検証される

### Changed

- vibrato.lua / vaporetto.lua の重複していたプロセス管理 (約 400 行) を
  tokenizer_engine に統合。vibrato の非同期フォールバックが 1 行あたり
  2 回プロセスに問い合わせていた無駄も解消

### Added

- テキストオブジェクトを visual mode で使ったとき、選択範囲を置き換えずに
  元のアンカー (getpos("v")) を固定したまま延長するようになった
- 文末移動・テキストオブジェクトが空行による段落境界を尊重するように
  なった (`)` は段落末で止まり、`is` / `as` は段落を跨がない)
- property-based テスト (決定論的乱数による文末検出・分節分割の不変条件
  検証 100 ケースを CI で実行)

### Changed

- spider の function patterns 契約に準拠: 境界関数は常に**元の行がバイト
  座標**で渡され、移動方向が `backwards` フラグで渡されるようになった
  (nvim-spider への PR で提案)。これにより lua-utf8 への依存を完全に削除。
  vibrato / vaporetto / TinySegmenter の各パターン関数も大幅に簡素化

## [1.1.0] - 2026-09-13

### Fixed

- 全角ピリオド (．) が文末として認識されない問題を修正
  (END_CHARS に追加し、常に文末として扱う)
- ひらがな・カタカナ・漢字の直後に ASCII ピリオドがある場合、
  直後が日本語文字なら文末として扱う (ファイル名 "ファイル.txt" は
  直後が英数字のため分割しない)
- 日英混在テキストの境界ケースを網羅したテストを追加
  (URL・省略形・小数点・全角/半角ピリオド・複合終端符)

### Fixed

- `setup()` 内で debounce 用タイマーをイベントのたびに生成しており、
  デバウンスが機能していなかった問題。タイマーを setup 時に 1 回だけ
  生成してイベント間で共有するようにした
- `bunsetsu.lemma_under_cursor()` が Vibrato 未設定時に常に nil を返して
  いた問題。同梱 TinySegmenter にフォールバックし、表層形を返す
  (品詞・読みは空)

### Changed

- `:checkhealth bunsetsu` が Vibrato 未設定を警告ではなく情報として表示し、
  同梱 TinySegmenter の分割テストを行うようにした

## [1.0.1] - 2026-09-07

### Added

- テキストオブジェクト: `bunsetsu._commands.textobj` の
  `sentence(outer)` / `phrase(outer)`。`is` / `as` (文) と `iW` / `aW`
  (文節) を日本語・英語どちらでも使える。選択範囲の確定 (selection /
  virtualedit / 強制モーション) は nvim-spider の setEndpoints に委譲
- 文末移動のオペレータ対応: `bunsetsu._commands.sentence` の
  `operator_next_end()` / `operator_prev_end()`。`d)` / `c(` / `y2)` の
  ように使える
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

- `debounce` 設定がコードから参照されていなかった問題。
  TextChangedI の連続変更時に変更行の再分割を debounce 設定 (ms) で
  まとめるように接続した
- `splitpat` 設定が実際には無視されていた問題。シンプルな文字クラス
  (例: `"[?!、。]"`, `"[、]"`) を解釈し、解釈できないパターンは既定値に
  フォールバックする。`:BunsetsuSplit` と Vibrato バックエンドの全文モード
  にも splitpat が効くようになった
- UniDic 辞書ファイルが読めない場合に `bunsetsu.lemma()` がエラーではなく
  nil を返すようになった

### Changed

- setup() の autocmd 登録とバッファ状態管理を `_core.lifecycle` に分離
  (init.lua は公開 API の facade に)
- highlight.lua の位置走査を `segment.word_positions` に統一
  (ハイライト対象外の語で検索位置が進まない潜在バグの修正を含む)

### Changed

- 未使用の util ヘルパ (line_len / at_line_end / set_cursor0) と
  Makefile の未使用変数を削除
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
