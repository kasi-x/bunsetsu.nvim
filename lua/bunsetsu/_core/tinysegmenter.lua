-- TinySegmenter 0.2 -- Super compact Japanese tokenizer in JavaScript
-- (c) 2008 Taku Kudo <taku@chasen.org>
-- TinySegmenter is freely distributable under the terms of a new BSD licence.
-- For details, see http://chasen.org/~taku/software/TinySegmenter/LICENCE.txt
--
-- This Lua implementation is a port of:
--   * the ES-module version modified by Taisuke Fukuno (2022-05-30)
--   * the Lua port by OKABE Gota (2024-11-29), from tinysegmenter.nvim
--
-- Unlike tinysegmenter.nvim (which hardcodes the default model), this module
-- accepts a model table as an argument so that multiple trained models
-- (e.g. knbc_bunsetu, wpci_bunsetu, jeita, rwcp) can be used.

local utf8 = require("bunsetsu._core.utf8")

---@param c string
---@param arr string[]
---@return boolean
local function checkCharByArr(c, arr)
  for _, v in ipairs(arr) do
    if v == c then
      return true
    end
  end
  return false
end

---@param c string
---@param from_char string
---@param to_char string
---@return boolean
local function checkCharByCP(c, from_char, to_char)
  local cp_c = utf8.codepoint(c)
  local cp_fc = utf8.codepoint(from_char)
  local cp_tc = utf8.codepoint(to_char)
  return cp_c >= cp_fc and cp_tc >= cp_c
end

---Classify a single character into a character type used by the model.
---Types: M (number), H (kanji), I (hiragana), K (katakana),
---       A (ascii), N (number), O (other).
---@param c string
---@return string
local function checkCharType(c)
  if
    checkCharByArr(c, {
      "一",
      "二",
      "三",
      "四",
      "五",
      "六",
      "七",
      "八",
      "九",
      "十",
      "百",
      "千",
      "万",
      "億",
      "兆",
    })
  then
    return "M"
  end
  if checkCharByCP(c, "一", "龠") or checkCharByArr(c, { "々", "〆", "ヵ", "ヶ" }) then
    return "H"
  end
  if checkCharByCP(c, "ぁ", "ん") then
    return "I"
  end
  if
    checkCharByCP(c, "ァ", "ヴ")
    or checkCharByCP(c, "ァ", "ﾝ")
    or checkCharByArr(c, { "ー", "ﾞ", "ﾟ" })
  then
    return "K"
  end
  if
    checkCharByCP(c, "a", "z")
    or checkCharByCP(c, "A", "Z")
    or checkCharByCP(c, "ａ", "ｚ")
    or checkCharByCP(c, "Ａ", "Ｚ")
  then
    return "A"
  end
  if checkCharByCP(c, "0", "9") or checkCharByCP(c, "０", "９") then
    return "N"
  end
  return "O"
end

---Lookup a weight from a model table, returning 0 when missing.
---@param model table<string, table|number>
---@param key string
---@param sub string
---@return number
local function ts(model, key, sub)
  local t = model[key]
  if type(t) ~= "table" then
    return 0
  end
  local v = t[sub]
  if v == nil then
    return 0
  end
  return v
end

---Segment a string into tokens using the given TinySegmenter model.
---@param model table<string, any>
---@param input string
---@return string[]
local function segment(model, input)
  if input == nil or input == "" then
    return {}
  end
  local result = {}
  local seg = { "B3", "B2", "B1" }
  local ctype = { "O", "O", "O" }
  for _, v in utf8.codes(input) do
    seg[#seg + 1] = v
    ctype[#ctype + 1] = checkCharType(v)
  end
  seg[#seg + 1] = "E1"
  seg[#seg + 1] = "E2"
  seg[#seg + 1] = "E3"
  ctype[#ctype + 1] = "O"
  ctype[#ctype + 1] = "O"
  ctype[#ctype + 1] = "O"

  local word = seg[4]
  local p1 = "U"
  local p2 = "U"
  local p3 = "U"
  for i = 5, #seg - 3, 1 do
    local score = model.BIAS
    local w1 = seg[i - 3]
    local w2 = seg[i - 2]
    local w3 = seg[i - 1]
    local w4 = seg[i]
    local w5 = seg[i + 1]
    local w6 = seg[i + 2]
    local c1 = ctype[i - 3]
    local c2 = ctype[i - 2]
    local c3 = ctype[i - 1]
    local c4 = ctype[i]
    local c5 = ctype[i + 1]
    local c6 = ctype[i + 2]
    score = score + ts(model, "UP1", p1)
    score = score + ts(model, "UP2", p2)
    score = score + ts(model, "UP3", p3)
    score = score + ts(model, "BP1", p1 .. p2)
    score = score + ts(model, "BP2", p2 .. p3)
    score = score + ts(model, "UW1", w1)
    score = score + ts(model, "UW2", w2)
    score = score + ts(model, "UW3", w3)
    score = score + ts(model, "UW4", w4)
    score = score + ts(model, "UW5", w5)
    score = score + ts(model, "UW6", w6)
    score = score + ts(model, "BW1", w2 .. w3)
    score = score + ts(model, "BW2", w3 .. w4)
    score = score + ts(model, "BW3", w4 .. w5)
    score = score + ts(model, "TW1", w1 .. w2 .. w3)
    score = score + ts(model, "TW2", w2 .. w3 .. w4)
    score = score + ts(model, "TW3", w3 .. w4 .. w5)
    score = score + ts(model, "TW4", w4 .. w5 .. w6)
    score = score + ts(model, "UC1", c1)
    score = score + ts(model, "UC2", c2)
    score = score + ts(model, "UC3", c3)
    score = score + ts(model, "UC4", c4)
    score = score + ts(model, "UC5", c5)
    score = score + ts(model, "UC6", c6)
    score = score + ts(model, "BC1", c2 .. c3)
    score = score + ts(model, "BC2", c3 .. c4)
    score = score + ts(model, "BC3", c4 .. c5)
    score = score + ts(model, "TC1", c1 .. c2 .. c3)
    score = score + ts(model, "TC2", c2 .. c3 .. c4)
    score = score + ts(model, "TC3", c3 .. c4 .. c5)
    score = score + ts(model, "TC4", c4 .. c5 .. c6)
    score = score + ts(model, "UQ1", p1 .. c1)
    score = score + ts(model, "UQ2", p2 .. c2)
    score = score + ts(model, "UQ3", p3 .. c3)
    score = score + ts(model, "BQ1", p2 .. c2 .. c3)
    score = score + ts(model, "BQ2", p2 .. c3 .. c4)
    score = score + ts(model, "BQ3", p3 .. c2 .. c3)
    score = score + ts(model, "BQ4", p3 .. c3 .. c4)
    score = score + ts(model, "TQ1", p2 .. c1 .. c2 .. c3)
    score = score + ts(model, "TQ2", p2 .. c2 .. c3 .. c4)
    score = score + ts(model, "TQ3", p3 .. c1 .. c2 .. c3)
    score = score + ts(model, "TQ4", p3 .. c2 .. c3 .. c4)
    local p = "O"
    if score > 0 then
      result[#result + 1] = word
      word = ""
      p = "B"
    end
    p1 = p2
    p2 = p3
    p3 = p
    word = word .. seg[i]
  end
  result[#result + 1] = word
  return result
end

return {
  segment = segment,
  checkCharType = checkCharType,
}
