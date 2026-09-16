---Vibrato バックエンドの自動セットアップ (ダウンロード / ビルド / 辞書導入)。
--
-- tokenize CLI を cargo でビルドし、辞書を vibrato の Releases から入手して
-- stdpath("data")/bunsetsu/vibrato/ 配下に導入する。導入後に
-- configuration.DATA.vibrato へパスを反映する。
--
-- 使い方:
--   :BunsetsuVibratoSetup [flavor]
--   require("bunsetsu").vibrato_setup({ flavor = "ipadic", force = true })
--   vibrato = { dict = "auto" } を設定すると、未導入なら setup() 時に自動実行
--
-- 必要なコマンド: cargo / tar / xz / curl または wget
-- 辞書アセットは vibrato v0.5.0 リリースに固定 (辞書が付属する最新リリース)。

local M = {}

---@class Bunsetsu.VibratoManifest
---@field version string ビルド元の vibrato タグ (例 "v0.5.2")
---@field flavor string 辞書の種類
---@field cmd string tokenize CLI の絶対パス
---@field dict string system.dic.zst の絶対パス
---@field installed_at string ISO8601 (UTC)

---既定のインストール先ルート (テストでは M._install_root を差し替える)。
M._install_root = nil

---辞書アセットが付属している vibrato リリース。
local DICT_TAG = "v0.5.0"

---flavor → v0.5.0 リリースの辞書アセット名。
---compact 付きは完全版よりかなり小さい (精度は若干劣る)。
---@type table<string, string>
local FLAVOR_ASSETS = {
  ["ipadic"] = "ipadic-mecab-2_7_0.tar.xz",
  ["unidic-mecab"] = "unidic-mecab-2_1_2.tar.xz",
  ["unidic-cwj"] = "unidic-cwj-3_1_1+compact.tar.xz",
  ["jumandic"] = "jumandic-mecab-7_0.tar.xz",
  ["naist-jdic"] = "naist-jdic-mecab-0_6_3b.tar.xz",
}

---CLI のビルド元タグの既定値 (vibrato の最新安定版)。
local DEFAULT_VERSION = "v0.5.2"

---@return string
local function root()
  return M._install_root or (vim.fn.stdpath("data") .. "/bunsetsu/vibrato")
end

---@return string
local function manifest_path(rdir)
  return (rdir or root()) .. "/manifest.json"
end

---manifest を読む。無い・壊れている・参照先ファイルが消えている場合は nil。
---@param rdir? string インストール先ルート (省略時は既定)
---@return Bunsetsu.VibratoManifest|nil
function M.read_manifest(rdir)
  local path = (rdir and rdir or root()) .. "/manifest.json"
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local body = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, body)
  if
    not ok
    or type(data) ~= "table"
    or type(data.cmd) ~= "string"
    or type(data.dict) ~= "string"
  then
    return nil
  end
  if vim.fn.filereadable(data.dict) == 0 or vim.fn.executable(data.cmd) == 0 then
    return nil
  end
  return data
end

---flavor を辞書アセット名に解決する。
---@param flavor string
---@return string asset
---@return nil
function M.flavor_asset(flavor)
  local asset = FLAVOR_ASSETS[flavor]
  if not asset then
    error(
      ("bunsetsu: 未知の vibrato flavor '%s' (利用可能: %s)"):format(
        flavor,
        table.concat(vim.tbl_keys(FLAVOR_ASSETS), ", ")
      )
    )
  end
  return asset
end

---ダウンロードコマンドを作る (curl が無ければ wget)。
---@param dest string
---@param url string
---@return string[]
local function download_cmd(dest, url)
  if vim.fn.executable("curl") == 1 then
    return { "curl", "-fsSL", "-o", dest, url }
  end
  return { "wget", "-q", "-O", dest, url }
end

---セットアップの手順 (ダウンロード / 展開 / ビルド) を返す。純粋関数。
---@param rdir string インストール先ルート
---@param opts { flavor: string, version: string }
---@return { msg: string, cmd: string[], cwd?: string }[]
function M.steps(rdir, opts)
  local asset = M.flavor_asset(opts.flavor)
  local version = opts.version
  local tmp = rdir .. "/tmp"
  local src_archive = tmp .. "/vibrato-" .. version .. ".tar.gz"
  -- GitHub のソース tarball は vibrato-<tag without v>/ に展開される
  local src_dir = tmp .. "/vibrato-" .. version:gsub("^v", "")
  local dict_archive = tmp .. "/" .. asset

  return {
    {
      msg = "bunsetsu: Vibrato ソースをダウンロード中 (" .. version .. ")",
      cmd = download_cmd(
        src_archive,
        "https://github.com/daac-tools/vibrato/archive/refs/tags/" .. version .. ".tar.gz"
      ),
    },
    {
      msg = "bunsetsu: ソースを展開中",
      cmd = { "tar", "xzf", src_archive, "-C", tmp },
    },
    {
      msg = "bunsetsu: tokenize CLI をビルド中 (数分かかることがあります)",
      cmd = { "cargo", "build", "--release", "-p", "tokenize" },
      cwd = src_dir,
    },
    {
      msg = "bunsetsu: 辞書 (" .. opts.flavor .. ") をダウンロード中",
      cmd = download_cmd(
        dict_archive,
        "https://github.com/daac-tools/vibrato/releases/download/" .. DICT_TAG .. "/" .. asset
      ),
    },
    {
      msg = "bunsetsu: 辞書を展開中",
      cmd = { "tar", "xJf", dict_archive, "-C", tmp },
    },
  }
end

---導入に必要なコマンドの不足一覧を返す。
---@return string[] missing
function M.missing_deps()
  local missing = {}
  for _, tool in ipairs({ "cargo", "tar", "xz" }) do
    if vim.fn.executable(tool) == 0 then
      missing[#missing + 1] = tool
    end
  end
  if vim.fn.executable("curl") == 0 and vim.fn.executable("wget") == 0 then
    missing[#missing + 1] = "curl または wget"
  end
  return missing
end

---@param msg string
---@param level? number
local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "bunsetsu.nvim" })
end

---展開済み辞書の system.dic.zst を探す。
---@param tmp string
---@param asset string
---@return string|nil
local function find_dict(tmp, asset)
  local base = tmp .. "/" .. asset:gsub("%.tar%.xz$", "")
  for _, cand in ipairs({ base .. "/system.dic.zst", base .. "/*/system.dic.zst" }) do
    local hit = vim.fn.glob(cand)
    if hit ~= "" then
      return hit
    end
  end
  return nil
end

---セットアップを実行する (非同期)。完了時に manifest を on_done へ渡す。
---@param opts? { flavor?: string, version?: string, force?: boolean, root?: string }
---@param on_done? fun(manifest: Bunsetsu.VibratoManifest)
---@return boolean 開始したか (導入済み・実行中・依存不足の場合は false)
function M.run(opts, on_done)
  opts = opts or {}
  local rdir = opts.root or root()
  local flavor = opts.flavor or "ipadic"
  local version = opts.version or DEFAULT_VERSION

  if M._running then
    notify("bunsetsu: Vibrato のセットアップが既に実行中です", vim.log.levels.WARN)
    return false
  end

  local manifest = M.read_manifest(rdir)
  if manifest and not opts.force then
    notify(
      ("bunsetsu: Vibrato は導入済みです (%s / %s)。再導入は force を指定してください"):format(
        manifest.version,
        manifest.flavor
      )
    )
    if on_done then
      on_done(manifest)
    end
    return false
  end

  local missing = M.missing_deps()
  if #missing > 0 then
    notify(
      "bunsetsu: Vibrato の自動セットアップに必要なコマンドがありません: "
        .. table.concat(missing, ", ")
        .. "\n手動での導入方法は README の Backends セクションを参照してください",
      vim.log.levels.ERROR
    )
    return false
  end

  local ok, err = pcall(M.flavor_asset, flavor)
  if not ok then
    notify(err, vim.log.levels.ERROR)
    return false
  end

  local tmp = rdir .. "/tmp"
  vim.fn.mkdir(tmp, "p")
  vim.fn.mkdir(rdir .. "/bin", "p")
  vim.fn.mkdir(rdir .. "/dict", "p")

  local steps = M.steps(rdir, { flavor = flavor, version = version })
  local bin_src = tmp .. "/vibrato-" .. version:gsub("^v", "") .. "/target/release/tokenize"
  local bin_dst = rdir .. "/bin/tokenize"
  local dict_dst = rdir .. "/dict/system.dic.zst"

  M._running = true

  local function finish(manifest_data)
    M._running = nil
    vim.fn.delete(tmp, "rf")
    if on_done then
      on_done(manifest_data)
    end
  end

  local function run_step(i)
    if i > #steps then
      -- 成果物を配置して manifest を書く
      local dict_src = find_dict(tmp, M.flavor_asset(flavor))
      if vim.fn.filereadable(bin_src) == 0 or not dict_src then
        M._running = nil
        notify(
          "bunsetsu: ビルド・ダウンロードの完了後、成果物が見つかりません ("
            .. bin_src
            .. ")",
          vim.log.levels.ERROR
        )
        return
      end
      assert(vim.uv.fs_rename(bin_src, bin_dst))
      assert(vim.uv.fs_rename(dict_src, dict_dst))
      local manifest_data = {
        version = version,
        flavor = flavor,
        cmd = bin_dst,
        dict = dict_dst,
        installed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      }
      local f = assert(io.open(manifest_path(rdir), "w"))
      f:write(vim.json.encode(manifest_data))
      f:close()
      finish(manifest_data)
      return
    end

    local step = steps[i]
    notify(step.msg)
    vim.system(step.cmd, { cwd = step.cwd, text = true }, function(r)
      vim.schedule(function()
        if r.code == 0 then
          run_step(i + 1)
        else
          local tail = tostring(r.stderr or "")
          if #tail > 400 then
            tail = tail:sub(-400)
          end
          M._running = nil
          notify(
            ("bunsetsu: Vibrato のセットアップに失敗しました: %s\n%s"):format(
              table.concat(step.cmd, " "),
              tail
            ),
            vim.log.levels.ERROR
          )
        end
      end)
    end)
  end

  run_step(1)
  return true
end

---checkhealth 用の状態サマリ。
---@return string|nil line 導入済みなら説明行、未導入なら nil
function M.status()
  local m = M.read_manifest()
  if not m then
    return nil
  end
  return ("自動セットアップ済み: vibrato %s / 辞書 %s (%s)"):format(
    m.version,
    m.flavor,
    m.dict
  )
end

return M
