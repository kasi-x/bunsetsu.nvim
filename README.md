# bunsetsu.nvim

*Move by Japanese phrase units (文節, bunsetsu) in Neovim.*

bunsetsu.nvim brings phrase-level motion and jumping to Japanese text. Instead of
stopping at every character or word, `w` / `b` / `e` / `ge` land on phrase
boundaries — 「これは」「文章です。」 — while ASCII text keeps normal word
motion. It extends [nvim-spider](https://github.com/chrisgrieser/nvim-spider)
and [flash.nvim](https://github.com/folke/flash.nvim), and ships a Lua port of
[TinySegmenter](https://github.com/sirasagi62/tinysegmenter.nvim)-trained
phrase-segmentation models, so it works offline with no extra binaries. For
higher accuracy you can plug in the [Vibrato](https://github.com/daac-tools/vibrato)
or [Vaporetto](https://github.com/daac-tools/vaporetto) tokenizers instead.

## Features

- **nvim-spider integration** — register one boundary function via
  `customPatterns`; on Japanese text motions become phrase-wise, on ASCII they
  delegate to nvim-spider
- **flash.nvim integration** — precomputed phrase list as a flash matcher with
  labels, correct across mixed ASCII/Japanese lines
- **Two modes** — current-line segmentation for instant response, plus a
  whole-buffer mode that precomputes segments and recomputes only edited lines
- **Resident-process backends** — Vibrato/Vaporetto run as sync + async jobs so
  motions never block the editor
- **POS highlighting & lemma lookup** — underline morphemes by part of speech
  and fetch surface / lemma / reading / POS under the cursor (Vibrato)
- **`:BunsetsuSplit`** — rewrite a range as space-separated phrases (分かち書き)
- **`:checkhealth bunsetsu`** — built-in setup verification

## Requirements

- Neovim 0.11+ (CI tests 0.11, 0.12, stable, nightly)
- Optional: [nvim-spider](https://github.com/chrisgrieser/nvim-spider) and
  [flash.nvim](https://github.com/folke/flash.nvim) for the integrations
- Optional: [lua-utf8](https://luarocks.org/modules/xiaoyaocrack/lua-utf8)
  (`luarocks install lua-utf8`) for byte-safe operation of the CLI backends
- Optional: Vibrato or Vaporetto CLI + dictionary for the external backends

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "kasi-x/bunsetsu.nvim",
    version = "v1.*",
    dependencies = { "chrisgrieser/nvim-spider", "folke/flash.nvim" },
    opts = {},
}
```

The plugin is also published on LuaRocks (see `bunsetsu-scm-1.rockspec`):

```sh
luarocks install bunsetsu.nvim --dev
```

Run `:checkhealth bunsetsu` to verify your setup.

## Usage

### nvim-spider: phrase-wise `w` / `b` / `e` / `ge`

Register the bundled TinySegmenter boundary function with spider:

```lua
require("spider").setup({
    consistentOperatorPending = true,
    customPatterns = {
        patterns = { require("bunsetsu._commands.spider").pattern },
        overrideDefault = false,
    },
})
```

On mixed text like `This is 天堂 真矢。` the phrases become
`This | is | 天堂 | 真矢。` and `w` moves `This` → `is` → `天堂` → `真矢。`.

To use an external tokenizer's segmentation instead, register
`require("bunsetsu").vibrato_pattern("bunsetsu")` or
`require("bunsetsu").vaporetto_pattern("bunsetsu")` (mode `"word"` keeps word
boundaries, `"bunsetsu"` merges particles/auxiliaries into the preceding word).

### flash.nvim: label-jump to phrases

```lua
vim.keymap.set("n", "<leader>j", function()
    require("bunsetsu._commands.plugins.flash").jump()
end, { desc = "Jump to bunsetsu" })
```

Japanese phrases and ASCII words share one segment list, so labels stay correct
on mixed lines.

### Command and Lua API

| Command / API | Description |
| --- | --- |
| `:[range]BunsetsuSplit` | Replace the range with phrase-separated text (`splitsep`, default `" "`) |
| `require("bunsetsu").full_segments()` | Whole-buffer segment list (`{ lnum, col, colend, idx, text }`) |
| `require("bunsetsu").highlight([enabled])` | Toggle POS underline highlighting (Vibrato) |
| `require("bunsetsu").lemma_under_cursor()` | `{ surface, lemma, reading, pos }` under the cursor (ASCII uses `<cword>`, Japanese uses Vibrato) |
| `require("bunsetsu").lemma(surface)` | UniDic lookup for a surface form (`lemma.dict_path` required) |
| `require("bunsetsu").models()` | Configured backend names |

## Configuration

Configuration goes in `vim.g.bunsetsu_configuration`:

```lua
vim.g.bunsetsu_configuration = {
    -- Phrase-segmentation model for the bundled TinySegmenter backend
    model = "knbc_bunsetu", -- knbc_bunsetu / wpci_bunsetu / jeita / rwcp
    -- Force a phrase boundary after these characters
    splitpat = "[?!、。]",
    -- Separator inserted by :BunsetsuSplit
    splitsep = " ",
    -- Debounce (ms) for invalidating the whole-buffer cache
    debounce = 50,
    -- Vibrato backend (optional; dictionary set = enabled)
    vibrato = {
        cmd = "vibrato", -- tokenize CLI
        dict = "",       -- MeCab-format dictionary path
    },
    -- Vaporetto backend (optional)
    vaporetto = {
        cmd = "predict", -- predict CLI
        model = "",      -- .model.zst path
    },
    -- UniDic lemma lookup (optional)
    lemma = {
        dict_path = "",  -- TSV: surface\tlemma\treading\tpos
    },
    -- POS underline highlighting (optional)
    highlight = {
        enabled = false,
    },
}
```

### Backends

- **TinySegmenter (default)** — the four bundled models segment offline, no
  setup needed. `model` selects between them.
- **Vibrato** — morphological analysis (word split + POS + lemma + reading) via
  the `vibrato tokenize` CLI and a MeCab-format dictionary (ipadic etc.). Set
  `vibrato.dict` to enable; whole-buffer mode, `:BunsetsuSplit`, highlighting
  and lemma lookup then run through it. Build with `cargo install vibrato`.
- **Vaporetto** — very fast pointwise-prediction tokenizer via the `predict`
  CLI:

  ```sh
  git clone https://github.com/daac-tools/vaporetto
  cd vaporetto
  cargo build --release -p predict
  # model, e.g. bccwj-suw+unidic_pos+pron:
  wget https://github.com/daac-tools/vaporetto-models/releases/download/v0.5.0/bccwj-suw+unidic_pos+pron.tar.xz
  tar xf bccwj-suw+unidic_pos+pron.tar.xz
  ```

  Point `vaporetto.cmd` and `vaporetto.model` at the binary and `.model.zst`.

See `:h bunsetsu-backends` for details.

## Development

No runtime dependencies. Tests use
[busted](https://lunarmodules.github.io/busted/) driven by Neovim's Lua
interpreter (see `.busted`):

```sh
# tests
eval $(luarocks path --lua-version 5.1 --bin)
busted .

# lint / format
make luacheck
make check-stylua
```

`tools/build_lemma_dict.py` generates the UniDic lemma TSV
(`make lemma LEMMA_CSV=lex_3_1.csv`) used by `lemma.dict_path`.

## License

[MIT](LICENSE) © 2026 kasi-x

The bundled TinySegmenter port follows the original
[BSD-3-Clause](https://github.com/sirasagi62/tinysegmenter.nvim) license
(© 2008 Taku Kudo); `lua/bunsetsu/_core/utf8.lua` is a CC0 UTF-8 helper.
