---Vaporetto バックエンド。単語分割を実行して文節境界を提供する。
--
-- Vaporetto (https://github.com/daac-tools/vaporetto) の predict CLI を使い、
-- 日本語を単語分割する。
--
-- 2種類のプロセスを使う:
--   * sync_job  : 同期プロセス。spider の pattern や lemma 取得などの
--                1リクエスト1レスポンスに使う (vim.wait でブロック)。
--   * async_job : 非同期プロセス。全文プリロード・行の再分割に使う。
--                vim.wait を使わないため、タイマーや編集処理と競合しない。
--
-- プロセスを分離することで、同期・非同期の競合を根本的に排除する。

local config = require("bunsetsu._core.configuration")

local M = {}

local lang = require("bunsetsu._core.lang")

-- M.is_particle への前方参照 (pattern 内で使用)
local is_particle

---日本語を含む行かどうか。
---@param line string
---@return boolean
local function has_japanese(line)
  return lang.has_japanese(line)
end

-- ---------------------------------------------------------------------------
-- チャンネル管理
-- ---------------------------------------------------------------------------

---チャンネルが開いているか。
---@param chan number|nil
---@return boolean
local function chan_is_open(chan)
  if not chan or chan <= 0 then
    return false
  end
  local info = vim.api.nvim_get_chan_info(chan)
  -- pty の jobstart は stream が "job"、mode は "bytes" になる
  return info and info.stream == "job"
end

---@class ProcState
---@field job number|nil
---@field ready boolean
---@field in_buffer string
---@field out_queue string[]
---@field sent number
---@field recv number

---同期プロセス (spider pattern / lemma 用)
local sync_state = {
  job = nil,
  ready = false,
  in_buffer = "",
  out_queue = {},
  sent = 0,
  recv = 0,
}

---非同期プロセス (全文プリロード / 行再分割用)
local async_state = {
  job = nil,
  ready = false,
  in_buffer = "",
  out_queue = {},
  sent = 0,
  recv = 0,
}

---予測プロセスを起動する。既に起動済みなら何もしない。
---@param kind "sync"|"async"
---@return number|false チャンネルID、失敗時 false
local function ensure_job(kind)
  local state = kind == "sync" and sync_state or async_state
  if chan_is_open(state.job) then
    return state.job
  end

  local vaporetto = config.DATA.vaporetto
  local cmd = vaporetto.cmd or "predict"
  local model = vaporetto.model
  if not model or model == "" then
    return false
  end

  state.in_buffer = ""
  state.out_queue = {}
  state.sent = 0
  state.recv = 0

  state.job = vim.fn.jobstart({ cmd, "--model", model, "--predict-tags" }, {
    pty = true, -- predict は stdout が tty のときだけ flush するため必要
    on_stdout = function(_, data)
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          state.in_buffer = state.in_buffer .. chunk
          local lines = vim.split(state.in_buffer, "[\r\n]+", { plain = false })
          state.in_buffer = table.remove(lines)
          for _, line in ipairs(lines) do
            if line:find("Start tokenization") then
              state.ready = true
            elseif line:find("Loading model file") or line:find("^Elapsed:") then
              -- スキップ
            elseif line ~= "" and line:find("/") then
              -- pty のエコーバック (分割結果以外) は / を含まないので除外
              state.out_queue[#state.out_queue + 1] = line
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

-- ---------------------------------------------------------------------------
-- 同期プロセス
-- ---------------------------------------------------------------------------

---同期 predict を実行して出力行を返す。
---@param line string 入力行
---@return string output predict の出力 (1行)
local function sync_predict(line)
  local job = ensure_job("sync")
  if not job then
    return ""
  end

  local req_id = sync_state.sent
  sync_state.sent = sync_state.sent + 1

  vim.fn.chansend(job, line .. "\n")

  -- レスポンスが来るまで待つ (predict は送信順に出力する)
  vim.wait(5000, function()
    return sync_state.recv > req_id
  end, 5)

  if sync_state.recv <= req_id then
    return ""
  end

  local out = table.remove(sync_state.out_queue, 1)
  return out or ""
end

---predict-tags 出力 "単語/品詞/読み ..." を単語と位置に分解する。
---@param out string predict の出力
---@param line string 元の行 (位置計算用)
---@return string[] words
---@return number[] positions
local function parse_tokens(out, line)
  local words = {}
  local positions = {}
  local search_from = 1
  for token in out:gmatch("%S+") do
    local parts = vim.split(token, "/", { plain = true })
    local tok = parts[1] or ""
    if tok == "\\" then
      search_from = search_from + 1
    elseif tok ~= "" then
      local found = vim.fn.stridx(line, tok, search_from - 1) + 1
      if found <= 0 then
        found = search_from
      end
      words[#words + 1] = tok
      positions[#positions + 1] = found
      search_from = found + #tok
    end
  end
  return words, positions
end

---Vaporetto で行を単語分割する。失敗時は空配列。
---日本語を含まない行は分割せず空配列を返す。
---@param line string
---@return string[] words 単語の文字列
---@return number[] positions 各単語の開始位置 (1-based byte)
function M.tokenize(line)
  if not has_japanese(line) then
    return {}, {}
  end
  local out = sync_predict(line)
  if out == "" then
    return {}, {}
  end
  return parse_tokens(out, line)
end

---Vaporetto で行を単語分割し、各語の POS タグを返す。
---@param line string
---@return string[] words 単語
---@return string[] tags POS タグ (例: "名詞-普通名詞-サ変可能")
function M.tokenize_with_tags(line)
  if not has_japanese(line) then
    return {}, {}
  end
  local out = sync_predict(line)
  if out == "" then
    return {}, {}
  end
  local words = {}
  local tags = {}
  for token in out:gmatch("%S+") do
    local parts = vim.split(token, "/", { plain = true })
    if #parts >= 1 and parts[1] ~= "" and parts[1] ~= "\\" then
      words[#words + 1] = parts[1]
      tags[#tags + 1] = parts[2] or ""
    end
  end
  return words, tags
end

-- ---------------------------------------------------------------------------
-- 非同期プロセス
-- ---------------------------------------------------------------------------

---複数行を非同期で分割する (全文プリロード・行再分割用)。
---vim.wait を使わないため、編集処理やタイマーと競合しない。
---
---@param lines {lnum: number, line: string}[] 行番号と行の配列
---@param on_done fun(results: {lnum: number, line: string, words: string[], positions: number[]}[])
function M.tokenize_async(lines, on_done)
  if #lines == 0 then
    on_done({})
    return
  end
  local job = ensure_job("async")
  if not job then
    -- async プロセスがまだ ready でない場合は、同期にフォールバック
    local results = {}
    for _, item in ipairs(lines) do
      local words, positions = M.tokenize(item.line)
      results[#results + 1] = {
        lnum = item.lnum,
        line = item.line,
        words = words,
        positions = positions,
      }
    end
    on_done(results)
    return
  end

  -- async プロセスが起動直後で ready でない場合、短く待つ
  if not async_state.ready then
    vim.wait(10000, function()
      return async_state.ready
    end, 10)
  end

  local req_base = async_state.sent
  local results = {}
  local expected = #lines
  local received = 0
  local done = false

  for _, item in ipairs(lines) do
    vim.fn.chansend(job, item.line .. "\n")
    async_state.sent = async_state.sent + 1
  end

  local timer = vim.uv.new_timer()
  timer:start(
    0,
    5,
    vim.schedule_wrap(function()
      if done then
        return
      end
      while received < expected and async_state.recv > (req_base + received) do
        local out = table.remove(async_state.out_queue, 1)
        if out and out ~= "" then
          local item = lines[received + 1]
          local words, positions = parse_tokens(out, item.line)
          results[received + 1] = {
            lnum = item.lnum,
            line = item.line,
            words = words,
            positions = positions,
          }
          received = received + 1
        end
      end

      if received >= expected then
        done = true
        timer:stop()
        pcall(timer.close, timer)
        on_done(results)
      elseif not chan_is_open(job) then
        done = true
        timer:stop()
        pcall(timer.close, timer)
        while received < expected do
          local item = lines[received + 1]
          results[received + 1] = { lnum = item.lnum, line = item.line, words = {}, positions = {} }
          received = received + 1
        end
        on_done(results)
      end
    end)
  )
end

-- ---------------------------------------------------------------------------
-- spider 用パターン
-- ---------------------------------------------------------------------------

---現在行の単語分割結果をキャッシュから返す。
---@param line string
---@return string[] 単語の文字列
---@return number[] 各単語の開始位置 (1-based byte)
local linecache = nil

local function get_words(line)
  if linecache and linecache.line == line then
    return linecache.words, linecache.positions
  end
  local words, positions = M.tokenize(line)
  linecache = { line = line, words = words, positions = positions }
  return words, positions
end

---Vaporetto の単語分割結果を、spider の customPatterns に渡す境界関数に変換する。
---
---spider の関数パターンの規約 (spider.motion-logic 参照):
---   fn(line, searchOffset, key) -> number|false
---   line:        検索対象の行。backward のときは UTF-8 対応で反転済み。
---   searchOffset:現在位置 (1-based byte、backward 時は逆順座標)
---   key:        "w"|"e"|"b"|"ge"
---     w  = 次の単語の開始位置
---     e  = 次の単語の終端位置 (語の最後の文字の位置)
---     b  = 前の単語の開始位置 (line は反転済み、逆順座標で返す)
---     ge = 前の単語の終端位置 (spider が endOfWord を反転するため開始位置を返す)
---   戻り値:      searchOffset より大きい次の境界位置 (1-based byte)
---
---@param mode "word"|"bunsetsu" 境界の粒度
---@return fun(line: string, searchOffset: number, key: string): number|false
function M.pattern(mode)
  mode = mode or "word"
  return function(line, searchOffset, key)
    local backwards = key == "b" or key == "ge"

    -- spider は backward のとき line を string.reverse (バイト反転) して渡す。
    -- バイト反転は UTF-8 を壊すが、再び :reverse() すると元のバイト列に戻る。
    local original = backwards and line:reverse() or line

    local words, positions = get_words(original)
    if #words == 0 then
      return false
    end

    -- 文節境界 (開始位置と終端位置)
    local boundaries = {}
    local boundaryEnds = {}
    for i in ipairs(words) do
      if mode == "bunsetsu" and i > 1 and is_particle(words[i]) then
        -- 助詞を前の語に結合する: 終端を伸ばす
        if #boundaries > 0 then
          boundaryEnds[#boundaryEnds] = positions[i] + #words[i] - 1
        end
      else
        boundaries[#boundaries + 1] = positions[i]
        boundaryEnds[#boundaryEnds + 1] = positions[i] + #words[i] - 1
      end
    end

    if #boundaries == 0 then
      return false
    end

    -- key に応じて位置を調整 (終端位置 e/ge は boundaryEnds[i])
    local target = function(i)
      if key == "e" or key == "ge" then
        return boundaryEnds[i]
      end
      return boundaries[i]
    end

    if backwards then
      -- 逆順座標系: 反転済み行の座標で「searchOffset より大きい最小」を返す
      local candidates = {}
      for i in ipairs(boundaries) do
        local t = target(i)
        local rev = #line - t + 1
        if rev > searchOffset then
          candidates[#candidates + 1] = rev
        end
      end
      if #candidates == 0 then
        return false
      end
      return math.min(unpack(candidates))
    else
      local candidates = {}
      for i in ipairs(boundaries) do
        local t = target(i)
        if t > searchOffset then
          candidates[#candidates + 1] = t
        end
      end
      if #candidates == 0 then
        return false
      end
      return math.min(unpack(candidates))
    end
  end
end

---助詞・助動詞かどうかの簡易判定。
---@param word string
---@return boolean
function M.is_particle(word)
  local particles = {
    "は",
    "を",
    "に",
    "へ",
    "が",
    "と",
    "も",
    "で",
    "や",
    "か",
    "の",
    "ね",
    "よ",
    "ぞ",
    "な",
    "わ",
    "ず",
    "ば",
  }
  for _, p in ipairs(particles) do
    if word == p then
      return true
    end
  end
  local auxiliaries = { "です", "ます", "た", "ない", "いる", "ある" }
  for _, a in ipairs(auxiliaries) do
    if word == a then
      return true
    end
  end
  return false
end

is_particle = M.is_particle

-- ---------------------------------------------------------------------------
-- キャッシュ・プロセス管理
-- ---------------------------------------------------------------------------

---キャッシュをクリアする。
function M.clear_cache()
  linecache = nil
end

---常駐プロセスを終了する。
function M.stop()
  for _, state in ipairs({ sync_state, async_state }) do
    if chan_is_open(state.job) then
      vim.fn.jobstop(state.job)
    end
    state.job = nil
    state.ready = false
    state.in_buffer = ""
    state.out_queue = {}
    state.sent = 0
    state.recv = 0
  end
  linecache = nil
end

---同期プロセスが起動しているか。
---@return boolean
function M.is_running()
  return chan_is_open(sync_state.job)
end

return M
