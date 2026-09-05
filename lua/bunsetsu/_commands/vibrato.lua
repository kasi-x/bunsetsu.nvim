---Vibrato バックエンド。日本語の形態素解析 (単語分割 + 品詞 + 原形 + 読み)。
--
-- Vibrato (https://github.com/daac-tools/vibrato) の tokenize CLI を使い、
-- 日本語を単語分割する。MeCab 形式の辞書 (ipadic 等) を利用する。
--
-- 出力形式 (MeCab 形式):
--   表層形\t品詞,品詞細分類1,...,原形,読み,発音
--
-- 原形 (列7) と読み (列8) が出力に含まれるため、別途辞書引きは不要。
--
-- 2種類のプロセスを使う:
--   * sync_job  : 同期プロセス。spider の pattern や lemma 取得用。
--   * async_job : 非同期プロセス。全文プリロード・行再分割用。
-- プロセスを分離することで、同期・非同期の競合を排除する。

local config = require("bunsetsu._core.configuration")

-- lua-utf8 (必須)。spider も文字単位反転するため、これに合わせて使う。
local ok_utf8, lua_utf8 = pcall(require, "lua-utf8")
if not ok_utf8 then
  -- フォールバック: バイト反転 (UTF-8 は壊れるが、パターンは最低限動く)
  lua_utf8 = { reverse = function(s) return s:reverse() end }
end

local M = {}

-- M.is_particle への前方参照 (pattern 内で使用)
local is_particle

-- 日本語判定 (かな・漢字)
local JP = "[ぁ-んァ-ヶー一-龠]"

---日本語を含む行かどうか。
---@param line string
---@return boolean
local function has_japanese(line)
  return line:match(JP) ~= nil
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
  return info and info.stream == "job"
end

---@class ProcState
---@field job number|nil
---@field ready boolean
---@field in_buffer string
---@field out_queue string[][] 各レスポンス塊のトークン行 (EOS で確定)
---@field current_block string[] 組み立て中のトークン行
---@field sent number
---@field recv number

---同期プロセス (spider pattern / lemma 用)
local sync_state = {
  job = nil,
  ready = false,
  in_buffer = "",
  out_queue = {},
  current_block = {},
  sent = 0,
  recv = 0,
}

---非同期プロセス (全文プリロード / 行再分割用)
local async_state = {
  job = nil,
  ready = false,
  in_buffer = "",
  out_queue = {},
  current_block = {},
  sent = 0,
  recv = 0,
}

---Vibrato tokenize プロセスを起動する。既に起動済みなら何もしない。
---@param kind "sync"|"async"
---@return number|false チャンネルID、失敗時 false
local function ensure_job(kind)
  local state = kind == "sync" and sync_state or async_state
  if chan_is_open(state.job) then
    return state.job
  end

  local v = config.DATA.vibrato
  local cmd = v.cmd or "vibrato"
  local dict = v.dict
  if not dict or dict == "" then
    return false
  end

  state.in_buffer = ""
  state.out_queue = {}
  state.current_block = {}
  state.sent = 0
  state.recv = 0

  state.job = vim.fn.jobstart({ cmd, "-i", dict }, {
    pty = true, -- tokenize は stdout が tty のときだけ flush するため必要
    on_stdout = function(_, data)
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          state.in_buffer = state.in_buffer .. chunk
          local lines = vim.split(state.in_buffer, "[\r\n]+", { plain = false })
          state.in_buffer = table.remove(lines)
          for _, line in ipairs(lines) do
            if line:find("Ready to tokenize") then
              state.ready = true
            elseif line:find("Loading the dictionary") then
              -- スキップ
            elseif line == "EOS" then
              -- 1つのレスポンス塊 (EOS 区切り) が完了
              state.out_queue[#state.out_queue + 1] = state.current_block
              state.current_block = {}
              state.recv = state.recv + 1
            elseif line ~= "" and line:find("\t") then
              -- pty のエコーバック (分割結果以外) は \t を含まないので除外
              state.current_block[#state.current_block + 1] = line
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

  -- モデルロード完了まで待つ (sync のみ。async は待たず ready フラグで判定)
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
-- 出力パース
-- ----------------------------------------------------------------------------

---MeCab 形式の行 "表層形\t品詞,...,原形,読み,発音" を分解する。
---@param line string
---@return table { surface, pos, lemma, reading }
local function parse_line(line)
  local surface, features = line:match("^([^\t]+)\t(.+)$")
  if not surface then
    return nil
  end
  local cols = vim.split(features, ",", { plain = true })
  -- 列7=原形, 列8=読み (ipadic 形式)。無ければ表層形を使う。
  local lemma = cols[7] or surface
  local reading = cols[8] or ""
  return {
    surface = surface,
    pos = cols[1] or "",
    lemma = lemma,
    reading = reading,
  }
end

---同期 predict を実行して、行ごとのパース結果を返す。
---@param line string 入力行
---@return table[] tokens (parse_line の結果)
local function sync_predict(line)
  local job = ensure_job("sync")
  if not job then
    return {}
  end

  local req_id = sync_state.sent
  sync_state.sent = sync_state.sent + 1

  vim.fn.chansend(job, line .. "\n")

  vim.wait(5000, function()
    return sync_state.recv > req_id
  end, 5)

  if sync_state.recv <= req_id then
    return {}
  end

  -- 自分のレスポンス塊を取り出す (同期は直列なので先頭が自分の塊)
  local block = sync_state.out_queue[1]
  -- 消費済みの塊をクリア
  while #sync_state.out_queue > 0 do
    table.remove(sync_state.out_queue, 1)
  end
  if not block then
    return {}
  end

  local tokens = {}
  for _, out in ipairs(block) do
    local t = parse_line(out)
    if t then
      tokens[#tokens + 1] = t
    end
  end
  return tokens
end

---Vibrato で行を単語分割する。
---@param line string
---@return string[] words 表層形
---@return number[] positions 各単語の開始位置 (1-based byte)
function M.tokenize(line)
  if not has_japanese(line) then
    return {}, {}
  end
  local tokens = sync_predict(line)
  local words = {}
  local positions = {}
  local search_from = 1
  for _, t in ipairs(tokens) do
    local found = vim.fn.stridx(line, t.surface, search_from - 1) + 1
    if found <= 0 then
      found = search_from
    end
    words[#words + 1] = t.surface
    positions[#positions + 1] = found
    search_from = found + #t.surface
  end
  return words, positions
end

---Vibrato で行を分割し、各語の詳細情報 (品詞・原形・読み) を返す。
---@param line string
---@return string[] words
---@return table[] infos { pos, lemma, reading }
function M.tokenize_detailed(line)
  if not has_japanese(line) then
    return {}, {}
  end
  local tokens = sync_predict(line)
  local words = {}
  local infos = {}
  for _, t in ipairs(tokens) do
    words[#words + 1] = t.surface
    infos[#infos + 1] = { pos = t.pos, lemma = t.lemma, reading = t.reading }
  end
  return words, infos
end

-- ---------------------------------------------------------------------------
-- 非同期プロセス
-- ---------------------------------------------------------------------------

---複数行を非同期で分割する (全文プリロード・行再分割用)。
---@param lines {lnum: number, line: string}[] 行番号と行の配列
---@param on_done fun(results: {lnum: number, line: string, words: string[], positions: number[], infos: table[]}[])
function M.tokenize_async(lines, on_done)
  if #lines == 0 then
    on_done({})
    return
  end
  local job = ensure_job("async")
  if not job then
    -- async プロセスが利用できない場合は同期にフォールバック
    local results = {}
    for _, item in ipairs(lines) do
      local words, positions = M.tokenize(item.line)
      local _, infos = M.tokenize_detailed(item.line)
      results[#results + 1] = {
        lnum = item.lnum,
        line = item.line,
        words = words,
        positions = positions,
        infos = infos,
      }
    end
    on_done(results)
    return
  end

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
      -- レスポンス (EOS 区切り) を収集する
      -- async も直列なので、out_queue の先頭から順に自分の塊を取る
      while received < expected and async_state.recv > (req_base + received) do
        local words = {}
        local positions = {}
        local infos = {}
        local item = lines[received + 1]
        local block = async_state.out_queue[received + 1]
        if block then
          local search_from = 1
          for _, out in ipairs(block) do
            local t = parse_line(out)
            if t then
              local found = vim.fn.stridx(item.line, t.surface, search_from - 1) + 1
              if found <= 0 then
                found = search_from
              end
              words[#words + 1] = t.surface
              positions[#positions + 1] = found
              infos[#infos + 1] = { pos = t.pos, lemma = t.lemma, reading = t.reading }
              search_from = found + #t.surface
            end
          end
        end
        results[received + 1] = {
          lnum = item.lnum,
          line = item.line,
          words = words,
          positions = positions,
          infos = infos,
        }
        received = received + 1
      end

      -- 消費済みの塊をクリア
      while #async_state.out_queue > 0 do
        table.remove(async_state.out_queue, 1)
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
          results[received + 1] = { lnum = item.lnum, line = item.line, words = {}, positions = {}, infos = {} }
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

---現在行の単語分割結果 (品詞込み) をキャッシュから返す。
---@param line string
---@return string[] 単語の文字列
---@return number[] 各単語の開始位置 (1-based byte)
---@return table[] 各単語の詳細 { pos, lemma, reading }
local linecache = nil

local function get_words(line)
  if linecache and linecache.line == line then
    return linecache.words, linecache.positions, linecache.infos
  end
  local words, infos = M.tokenize_detailed(line)
  -- 位置を計算
  local positions = {}
  local search_from = 1
  for i, w in ipairs(words) do
    local found = vim.fn.stridx(line, w, search_from - 1) + 1
    if found <= 0 then
      found = search_from
    end
    positions[i] = found
    search_from = found + #w
  end
  linecache = { line = line, words = words, positions = positions, infos = infos }
  return words, positions, infos
end

---Vibrato の分割結果を、spider の customPatterns に渡す境界関数に変換する。
---@param mode "word"|"bunsetsu" 境界の粒度
---@return fun(line: string, searchOffset: number, key: string): number|false
function M.pattern(mode)
  mode = mode or "word"
  return function(line, searchOffset, key)
    local backwards = key == "b" or key == "ge"

    -- spider は backward のとき line を文字単位で反転して渡す (lua-utf8)。
    -- lua_utf8.reverse で元の文字列に戻す。
    local original = backwards and lua_utf8.reverse(line) or line

    local words, positions, infos = get_words(original)
    if #words == 0 then
      return false
    end

    -- 文節境界 (開始位置と終端位置)
    -- バイト位置 → 文字位置に変換する (spider は lua-utf8 で文字位置ベース)。
    -- lua_utf8.codes でバイト位置を走査し、文字インデックスを求める。
    local function byte_to_char(byte_idx)
      -- byte_idx は 1-based バイト。その文字の開始バイト位置を探す。
      local char_idx = 1
      for p, _ in lua_utf8.codes(original) do
        if p >= byte_idx then
          break
        end
        char_idx = char_idx + 1
      end
      return char_idx
    end

    local boundaries = {}
    local boundaryEnds = {}
    for i in ipairs(words) do
      if mode == "bunsetsu" and i > 1 and is_particle(infos[i].pos) then
        if #boundaries > 0 then
          -- 助詞を前の文節に結合: 終端を次の文字位置-1に更新
          boundaryEnds[#boundaryEnds] = byte_to_char(positions[i] + #words[i]) - 1
        end
      else
        boundaries[#boundaries + 1] = byte_to_char(positions[i])
        boundaryEnds[#boundaryEnds + 1] = byte_to_char(positions[i] + #words[i]) - 1
      end
    end

    if #boundaries == 0 then
      return false
    end

    local target = function(i)
      if key == "e" or key == "ge" then
        return boundaryEnds[i]
      end
      return boundaries[i]
    end

    if backwards then
      local candidates = {}
      for i in ipairs(boundaries) do
        local t = target(i)
        local rev = lua_utf8.len(line) - t + 1
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

---助詞・助動詞かどうかを品詞タグで判定する。
---ipadic の品詞大分類で「助詞」「助動詞」を結合対象とする。
---@param pos string 品詞大分類 (Vibrato の parse_line の pos)
---@return boolean
function M.is_particle(pos)
  if not pos or pos == "" then
    return false
  end
  -- 品詞大分類 (「助詞,係助詞」→「助詞」)
  local big = vim.split(pos, ",", { plain = true })[1]
  return big == "助詞" or big == "助動詞"
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
    state.current_block = {}
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
