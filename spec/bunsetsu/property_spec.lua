-- property-based テスト: 決定論的な擬似乱数でランダム行を生成し、
-- 文末検出と分節分割の不変条件を検証する。

describe("bunsetsu invariants (property-based)", function()
  local sentence = require("bunsetsu._core.sentence")
  local segment = require("bunsetsu._core.segment")
  local config = require("bunsetsu._core.configuration")

  -- 決定論的 LCG (実行ごとに同じ列になる)
  local seed = 20260913
  local function rand(n)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed % n
  end

  local TOKENS = {
    "これ",
    "は",
    "文章",
    "です",
    "。",
    "、",
    "bunsetsu",
    "X",
    "abc123",
    "hello",
    "world",
    "！",
    "？」",
    "Test",
    " ",
    "  ",
    "vim",
    "。",
  }

  local function random_line()
    local parts = {}
    for _ = 1, 3 + rand(10) do
      parts[#parts + 1] = TOKENS[rand(#TOKENS) + 1]
    end
    return table.concat(parts)
  end

  before_each(function()
    config.initialize_data_if_needed()
    config.resolve_data()
  end)

  describe("sentence.ends()", function()
    for case = 1, 60 do
      it(
        ("case %d: positions are ascending, in bounds, and on terminators"):format(case),
        function()
          local line = random_line()
          local ends = sentence.ends(line)
          local prev = 0
          for _, pos in ipairs(ends) do
            assert.is_true(pos > prev, "positions ascend")
            assert.is_true(pos >= 1 and pos <= #line, "positions within line")
            -- 文末位置のバイトは、文末文字・閉じ括弧・ASCII 記号のいずれか
            local b = line:byte(pos)
            assert.is_true(
              (b >= 0x21 and b <= 0x7E) or b >= 0x80,
              "ends on a terminator or closer byte"
            )
            prev = pos
          end
        end
      )
    end
  end)

  describe("segment.split_line()", function()
    for case = 1, 40 do
      it(("case %d: segcols are ascending, in bounds, and non-empty"):format(case), function()
        local line = random_line()
        local segcols = segment.split_line("knbc_bunsetu", line)
        local prev_end = 0
        for _, sc in ipairs(segcols) do
          assert.is_true(sc.segment ~= "", "non-empty segment")
          assert.is_true(sc.col >= 1 and sc.col <= #line, "col within line")
          assert.is_true(sc.colend >= sc.col and sc.colend <= #line, "colend within line")
          assert.is_true(sc.col > prev_end, "segments ascend and do not overlap")
          prev_end = sc.colend
        end
      end)
    end
  end)
end)
