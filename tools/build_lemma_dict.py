#!/usr/bin/env python3
"""UniDic lex_3_1.csv から bunsetsu 用の TSV 辞書を生成する。

出力: surface<TAB>lemma<TAB>reading<TAB>pos

列定義 (lex_3_1.csv):
  0  = 表層形 (見出し)
  4  = 品詞 (大分類: 動詞/名詞/形容詞/助動詞...)
  9  = 活用形 (終止形-一般 / 連用形-一般 / ...)
  10 = 読み (発音)
  11 = 語彙素 (原形)

選定ルール:
  - 動詞・形容詞は活用形でも「原形」を優先する (連用形-一般 → 終止形の語彙素)
  - それ以外 (名詞等) は最初の候補
  - 読みが `*` の行は除外

使い方:
  python3 tools/build_lemma_dict.py <lex_3_1.csv> <出力.tsv>
"""

import csv
import sys
from collections import defaultdict

# 動詞・形容詞の基本形 (終止形) とみなす活用形
_BASE_FORMS = {"終止形-一般", "終止形-通用", "終止形"}
_VERB_LIKE = {"動詞", "形容詞"}


def _score(entry):
    pos, _lemma, _reading, form = entry
    if pos in _VERB_LIKE:
        if form in _BASE_FORMS:
            return 0
        return 1  # 活用形 → 原形を引く
    if pos == "助動詞":
        return 3
    return 2  # 名詞など


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    src, dst = sys.argv[1], sys.argv[2]

    data = defaultdict(list)
    with open(src, newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if len(row) < 14:
                continue
            surface = row[0]
            pos = row[4]
            reading = row[10]
            lemma = row[11]
            form = row[9]
            if reading in ("", "*"):
                continue
            data[surface].append((pos, lemma, reading, form))

    count = 0
    with open(dst, "w", encoding="utf-8") as out:
        for surface, entries in data.items():
            best = min(entries, key=_score)
            pos, lemma, reading, _form = best
            out.write(f"{surface}\t{lemma}\t{reading}\t{pos}\n")
            count += 1

    print(f"wrote {count} entries to {dst}")


if __name__ == "__main__":
    main()
