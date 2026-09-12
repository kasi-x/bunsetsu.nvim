.PHONY: test luacheck stylua check-stylua

test:
	busted .

luacheck:
	luacheck lua plugin spec

check-stylua:
	stylua lua plugin spec --color always --check

stylua:
	stylua lua plugin spec

# 依存のダウンロード (Lua LSP 用)。bunsetsu 自体は外部依存ゼロ。
download-dependencies:
	mkdir -p .dependencies
	git clone --depth 1 https://github.com/LuaCATS/busted.git .dependencies/busted 2>/dev/null || true
	git clone --depth 1 https://github.com/LuaCATS/luassert.git .dependencies/luassert 2>/dev/null || true

# UniDic TSV 辞書 (lemma.tsv) を lex_3_1.csv から生成する。
# lex_3_1.csv は UniDic 3.1.1 に含まれる (https://clrd.ninjal.ac.jp/unidic/back_number.html)。
LEMMA_CSV ?= lex_3_1.csv
lemma:
	python3 tools/build_lemma_dict.py $(LEMMA_CSV) lemma.tsv

