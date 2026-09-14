---常駐トークナイザプロセスの共通エンジン。
--
-- sync / async の 2 接続を持ち、Vibrato・Vaporetto 両バックエンドの
-- プロセス管理 (pty・行分割・準備待ち・リクエストキュー・非同期バッチ) を
-- 一元化する。バックエンド固有の差分は spec として注入する。
--
-- spec:
--   build_cmd : fun(): string[]|nil
--       起動コマンド列。設定不足などで起動できないときは nil。
--   classify  : fun(line: string): string
--       出力行の種別判定。"ready" | "skip" | "result" | "eos"
--   block_mode: "eos" | "line"
--       "eos"  = "eos" 行でブロックを確定させる (vibrato の MeCab 出力)
--       "line" = result 行 1 行ごとにブロックを確定させる (vaporetto)

local M = {}

---@class Tokenizer.Engine
---@field spec table
---@field states table

---チャンネルが開いているか。
---@param chan number|nil
---@return boolean
local function chan_is_open(chan)
  if not chan or chan <= 0 then
    return false
  end
  local info = vim.api.nvim_get_chan_info(chan)
  -- pty の jobstart は stream が "job" になる
  return info and info.stream == "job"
end

---新しいエンジンを生成する。
---@param spec { build_cmd: fun(): string[]|nil, classify: fun(line: string): string, block_mode: string }
---@return Tokenizer.Engine
function M.new(spec)
  local engine = setmetatable({ spec = spec }, { __index = M })
  engine.states = {
    sync = {
      job = nil,
      ready = false,
      in_buffer = "",
      out_queue = {},
      current_block = {},
      sent = 0,
      recv = 0,
    },
    async = {
      job = nil,
      ready = false,
      in_buffer = "",
      out_queue = {},
      current_block = {},
      sent = 0,
      recv = 0,
    },
  }
  return engine
end

function M:ensure_job(kind)
  local state = self.states[kind]
  if chan_is_open(state.job) then
    return state.job
  end

  local cmd = self.spec.build_cmd()
  if not cmd then
    return false
  end

  state.in_buffer = ""
  state.out_queue = {}
  state.current_block = {}
  state.sent = 0
  state.recv = 0

  state.job = vim.fn.jobstart(cmd, {
    pty = true, -- tokenize は stdout が tty のときだけ flush するため必要
    on_stdout = function(_, data)
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          state.in_buffer = state.in_buffer .. chunk
          local lines = vim.split(state.in_buffer, "[\r\n]+", { plain = false })
          state.in_buffer = table.remove(lines)
          for _, line in ipairs(lines) do
            local line_kind = self.spec.classify(line)
            if line_kind == "ready" then
              state.ready = true
            elseif line_kind == "result" then
              if self.spec.block_mode == "eos" then
                state.current_block[#state.current_block + 1] = line
              else
                state.out_queue[#state.out_queue + 1] = { line }
                state.recv = state.recv + 1
              end
            elseif line_kind == "eos" then
              state.out_queue[#state.out_queue + 1] = state.current_block
              state.current_block = {}
              state.recv = state.recv + 1
            end
          end
        end
      end
    end,
    on_exit = function()
      state.job = nil
      state.ready = false
    end,
  })

  if not state.job or state.job <= 0 then
    state.job = nil
    return false
  end

  -- モデルロード完了まで待つ (sync のみ。async は待たず、ready フラグで判定)
  if kind == "sync" then
    state.ready = false
    vim.wait(10000, function()
      return state.ready
    end, 10)
    if not state.ready then
      vim.fn.jobstop(state.job)
      state.job = nil
      return false
    end
  end

  return state.job
end

---同期プロセスに 1 行を送り、対応するブロック (出力行の配列) を返す。
---タイムアウトや失敗時は nil。
---@param line string 入力行
---@return string[]|nil block
function M:sync_request(line)
  local state = self.states.sync
  local job = self:ensure_job("sync")
  if not job then
    return nil
  end

  local req_id = state.sent
  state.sent = state.sent + 1

  vim.fn.chansend(job, line .. "\n")

  vim.wait(5000, function()
    return state.recv > req_id
  end, 5)

  if state.recv <= req_id then
    return nil
  end

  local block = state.out_queue[1]
  while #state.out_queue > 0 do
    table.remove(state.out_queue, 1)
  end
  return block or {}
end

---lines を常駐 (async) プロセスに送り、ブロック単位で on_done に返す。
---on_done の results[i] = { item = lines[i], block = string[] }。
---プロセスが使えない場合や途中で切断された場合は、空ブロックで埋めて
---必ず on_done を呼ぶ (フォールバックは呼び出し側で行う)。
---@param lines {lnum: number, line: string}[] 行番号と行の配列
---@param on_done fun(results: {item: {lnum: number, line: string}, block: string[]}[])
function M:tokenize_async(lines, on_done)
  if #lines == 0 then
    on_done({})
    return
  end

  local state = self.states.async
  local job = self:ensure_job("async")

  if not state.ready then
    vim.wait(10000, function()
      return state.ready
    end, 10)
  end

  local req_base = state.sent
  local results = {}
  local expected = #lines
  local received = 0
  local done = false

  for _, item in ipairs(lines) do
    vim.fn.chansend(job, item.line .. "\n")
    state.sent = state.sent + 1
  end

  local timer = vim.uv.new_timer()
  local function finish()
    done = true
    timer:stop()
    pcall(timer.close, timer)
    on_done(results)
  end

  timer:start(
    0,
    5,
    vim.schedule_wrap(function()
      if done then
        return
      end
      while received < expected and state.recv > (req_base + received) and #state.out_queue > 0 do
        local block = table.remove(state.out_queue, 1)
        local item = lines[received + 1]
        results[received + 1] = { item = item, block = block or {} }
        received = received + 1
      end

      if received >= expected then
        finish()
      elseif not chan_is_open(job) then
        while received < expected do
          local item = lines[received + 1]
          results[received + 1] = { item = item, block = {} }
          received = received + 1
        end
        finish()
      end
    end)
  )
end

---常駐プロセスを終了し、状態を初期化する。
function M:stop()
  for _, state in pairs(self.states) do
    if chan_is_open(state.job) then
      vim.fn.jobstop(state.job)
    end
    state.job = nil
    state.ready = false
    state.in_buffer = ""
    state.out_queue = {}
    state.current_block = {}
    state.sent = 0
    state.recv = 0
  end
end

---同期プロセスが起動しているか。
---@return boolean
function M:is_running()
  return chan_is_open(self.states.sync.job)
end

return M
