---分節モデルのレジストリ。
--
-- 各モデルは「文字列を受け取って segment のリストを返す関数」を提供する。
-- 現在は TinySegmenter の4モデルを同梱している。
--
-- モデル固有の splitpat (強制区切りパターン) を持たせられるように、
-- モデルはテーブル { segment = fn, splitpat = string|nil } として登録する。

local tinysegmenter = require("bunsetsu._core.tinysegmenter")

local M = {}

---@class Jasegment.Model
---@field segment fun(input: string): string[]
---@field splitpat? string

---@type table<string, Jasegment.Model>
local registry = {}

local tinysegmenter_models = {
  knbc_bunsetu = "knbc_bunsetu",
  wpci_bunsetu = "wpci_bunsetu",
  jeita = "jeita",
  rwcp = "rwcp",
}

for name, modname in pairs(tinysegmenter_models) do
  local ok, model = pcall(require, "bunsetsu.models." .. modname)
  if ok then
    registry[name] = {
      segment = function(input)
        return tinysegmenter.segment(model, input)
      end,
    }
  end
end

---登録済みモデル名の一覧を返す。
---@return string[]
function M.list()
  local names = {}
  for name in pairs(registry) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

---モデル名から分割関数を取得する。
---@param model_name string
---@return fun(input: string): string[]|nil
function M.get(model_name)
  local model = registry[model_name]
  if model then
    return model.segment
  end
  return nil
end

---モデル固有の splitpat を返す。無ければ nil。
---@param model_name string
---@return string|nil
function M.splitpat(model_name)
  local model = registry[model_name]
  if model then
    return model.splitpat
  end
  return nil
end

---独自のモデルを登録する。
---@param name string
---@param segment fun(input: string): string[]
---@param splitpat? string
function M.register(name, segment, splitpat)
  registry[name] = { segment = segment, splitpat = splitpat }
end

return M
