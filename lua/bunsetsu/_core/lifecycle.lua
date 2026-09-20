---setup() のライフサイクル処理 (autocmd 登録とバッファ状態管理)。
--
-- init.lua (公開 API) から呼ばれる。このモジュール自体は公開 API を持たず、
-- autocmd の登録とバッファごとの状態追跡だけを担当する。

local configuration = require("bunsetsu._core.configuration")
local full = require("bunsetsu._commands.full")
local lang = require("bunsetsu._core.lang")
local util = require("bunsetsu._core.util")

local M = {}

---autocmd とバッファ状態の管理を登録する。
---@param opts? Bunsetsu.Config All extra customizations for this plugin.
function M.setup(opts)
  configuration.initialize_data_if_needed()
  configuration.resolve_data(opts)

  -- vibrato.auto_setup で未導入のときはバックグラウンドでセットアップする。
  -- 起動直後の I/O と競合しないよう auto_setup_delay ms (既定 3 秒) 待ってから
  -- 開始する (cargo ビルドのため数分かかることがある。完了時にバックエンドが
  -- 切替わる)
  if configuration.consume_auto_setup_needed() then
    vim.defer_fn(function()
      local data = configuration.DATA.vibrato
      require("bunsetsu._commands.vibrato_setup").run({
        flavor = data and data.flavor,
        version = data and data.version,
      }, configuration.apply_vibrato_manifest)
    end, configuration.DATA.vibrato.auto_setup_delay or 3000)
  end

  local augroup = vim.api.nvim_create_augroup("bunsetsu", { clear = true })

  local model_name = full.current_model

  -- 変更行の再分割は debounce 設定 (ms) でまとめる。insert 中の連続変更
  -- (TextChangedI) のたびにトークナイザへ投げないようにするため、タイマーは
  -- setup 時に 1 回だけ生成してイベント間で共有する (イベント毎に生成すると
  -- デバウンスにならず、timer オブジェクトも溜まる)。
  local debounced_line_refresh = util.debounce(augroup, function(lnum)
    full.refresh_line(model_name(), lnum)
  end, configuration.DATA.debounce)

  local function on_change(lnum)
    if lnum and lnum >= 1 then
      -- 変更行のみ非同期で再分割してキャッシュ更新
      debounced_line_refresh(lnum)
    else
      -- 全行キャッシュ破棄 (次回 full() 時に再構築)
      full.invalidate()
      vim.schedule(function()
        full.preload(model_name())
      end)
    end
  end

  -- バッファ行数の追跡 (変更で行数が変わった場合は全行再処理)
  local buf_line_counts = {}
  -- undo/redo の検出用 (seq_cur が変わったら undo/redo)
  local buf_undo_seqs = {}
  -- 日本語を含むバッファのみ追跡・再分割する。ASCII のみのバッファ
  -- (コード等) では、TextChanged ごとの undotree() 呼び出し (undo ツリー
  -- 全体の構築) が無駄に重いため、処理をすべてスキップする。
  -- フラグはバッファ進入時などのみ更新するため、ASCII バッファに入力した
  -- 日本語は次回進入時から対象になる (移動自体は full() が遅延計算するので
  -- 常に動作する)。
  local buf_is_jp = {}

  local function line_count_changed(buf)
    local cur = vim.api.nvim_buf_line_count(buf)
    local prev = buf_line_counts[buf]
    buf_line_counts[buf] = cur
    return prev ~= nil and prev ~= cur
  end

  -- undo/redo が行われたかどうかを seq_cur の変化で検出する。
  -- Neovim には Undo/Redo の autocmd イベントが無いため、これを追跡する。
  local function undo_occurred(buf)
    local cur = vim.fn.undotree().seq_cur
    local prev = buf_undo_seqs[buf]
    buf_undo_seqs[buf] = cur
    return prev ~= nil and prev ~= cur
  end

  ---バッファが日本語を含むかを更新する (先頭 500 行のみ走査)。
  local function refresh_jp_flag(buf)
    buf_is_jp[buf] = false
    local lines = vim.api.nvim_buf_get_lines(buf, 0, configuration.DATA.jp_scan_lines or 500, false)
    for _, line in ipairs(lines) do
      if lang.has_japanese(line) then
        buf_is_jp[buf] = true
        break
      end
    end
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if not buf_is_jp[buf] then
        return
      end
      if line_count_changed(buf) or undo_occurred(buf) then
        -- 行数が変わった、または undo/redo → 全行再処理
        on_change()
      else
        on_change(vim.fn.line("."))
      end
    end,
  })

  -- 品詞ハイライト用 namespace (highlight 設定が有効な場合に使用)
  local hl_namespace = vim.api.nvim_create_namespace("bunsetsu_highlight")
  local hl_enabled = configuration.DATA.highlight and configuration.DATA.highlight.enabled or false

  local function apply_highlight(buf)
    if not hl_enabled then
      return
    end
    local hl = require("bunsetsu._commands.highlight")
    hl.apply(buf, hl_namespace)
  end

  vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "BufEnter" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      refresh_jp_flag(buf)
      if not buf_is_jp[buf] then
        return
      end
      -- 全行キャッシュ破棄 + 全文をバックグラウンドで分割
      on_change()
      -- 品詞ハイライト (オプション)
      apply_highlight(buf)
      -- 行数・undo 位置の追跡をリセット
      buf_line_counts[buf] = vim.api.nvim_buf_line_count(buf)
      buf_undo_seqs[buf] = vim.fn.undotree().seq_cur
    end,
  })

  -- バッファ削除時に追跡テーブルを片付ける
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    pattern = "*",
    callback = function(event)
      buf_line_counts[event.buf] = nil
      buf_undo_seqs[event.buf] = nil
      buf_is_jp[event.buf] = nil
    end,
  })

  -- TextChanged でも変更行のハイライトを更新
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if hl_enabled and buf_is_jp[buf] then
        -- 全文再ハイライトは重いので、デバウンスして行単位で更新
        apply_highlight(buf)
      end
    end,
  })
end

return M
