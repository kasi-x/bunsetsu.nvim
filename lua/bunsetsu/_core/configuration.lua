--- All functions and data to help customize `bunsetsu` for this user.

local M = {}

-- NOTE: Don't remove this line. It makes the Lua module much easier to reload
vim.g.loaded_bunsetsu = false

---@type Bunsetsu.Config
M.DATA = {}

---@type Bunsetsu.Config
local _DEFAULTS = {
  model = "knbc_bunsetu",
  splitpat = "[?!、。]",
  splitsep = " ",
  debounce = 50,
  vibrato = {
    cmd = "vibrato",
    dict = "",
  },
  vaporetto = {
    cmd = "predict",
    model = "",
  },
  lemma = {
    -- UniDic TSV (surface<TAB>lemma<TAB>reading<TAB>pos)。
    -- lex_3_1.csv から `bunsetsu.tools` のスクリプトで生成する。
    dict_path = "",
  },
  highlight = {
    -- 品詞ごとにアンダーラインで色を付ける。
    enabled = false,
  },
}

--- Setup `bunsetsu` for the first time, if needed.
function M.initialize_data_if_needed()
  if vim.g.loaded_bunsetsu then
    return
  end

  M.DATA = vim.tbl_deep_extend("force", _DEFAULTS, vim.g.bunsetsu_configuration or {})

  vim.g.loaded_bunsetsu = true
end

--- Merge `data` with the user's current configuration.
---
---`vim.g.bunsetsu_configuration` はプラグイン読み込み順によっては
---`initialize_data_if_needed` の後に設定されることがあるため、ここで常に
---マージしてから data を適用する。
---
---@param data? Bunsetsu.Config All extra customizations for this plugin.
---@return Bunsetsu.Config # The configuration with 100% filled out values.
function M.resolve_data(data)
  M.initialize_data_if_needed()

  -- 後から設定された vim.g.bunsetsu_configuration を必ず反映する
  M.DATA = vim.tbl_deep_extend("force", M.DATA, vim.g.bunsetsu_configuration or {})
  M.DATA = vim.tbl_deep_extend("force", M.DATA, data or {})

  return M.DATA
end

return M
