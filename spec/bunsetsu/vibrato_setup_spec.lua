---Vibrato 自動セットアップ (ダウンロード / ビルド / 辞書導入) のテスト。
---外部コマンドは実行せず vim.system をモックする。
describe("bunsetsu.vibrato_setup (automatic Vibrato installation)", function()
  local vs = require("bunsetsu._commands.vibrato_setup")
  local config = require("bunsetsu._core.configuration")

  local tmp_root
  local system_calls
  local real_system

  before_each(function()
    config.initialize_data_if_needed()
    config.resolve_data()
    tmp_root = vim.fn.tempname()
    vs._install_root = tmp_root
    system_calls = {}
    real_system = vim.system
  end)

  after_each(function()
    -- luacheck: ignore 122
    vim.system = real_system
    vim.fn.delete(tmp_root, "rf")
    vs._install_root = nil
    vs._running = nil
    config.resolve_data({ vibrato = { cmd = "vibrato", dict = "" } })
  end)

  ---モック用のダマー成果物を作る (finalize が配置するファイル)。
  local function make_fake_artifacts(flavor)
    local asset = vs.flavor_asset(flavor)
    local dirs = {
      tmp_root .. "/tmp/vibrato-0.5.2/target/release",
      tmp_root .. "/tmp/" .. asset:gsub("%.tar%.xz$", ""),
    }
    for _, d in ipairs(dirs) do
      vim.fn.mkdir(d, "p")
    end
    local bin = dirs[1] .. "/tokenize"
    vim.fn.writefile({ "#!/bin/sh", "exit 0" }, bin)
    vim.uv.fs_chmod(bin, 493) -- 0o755
    vim.fn.writefile({ "dummy-dic" }, dirs[2] .. "/system.dic.zst")
  end

  ---vim.system をモックし、全ステップ成功にする。
  local function mock_system_success()
    -- luacheck: ignore 122
    vim.system = function(cmd, sys_opts, cb)
      system_calls[#system_calls + 1] = { cmd = cmd, cwd = sys_opts and sys_opts.cwd }
      cb({ code = 0, stdout = "", stderr = "" })
    end
  end

  describe("flavor_asset()", function()
    it("resolves known flavors to v0.5.0 release assets", function()
      assert.are.equal("ipadic-mecab-2_7_0.tar.xz", vs.flavor_asset("ipadic"))
      assert.are.equal("unidic-cwj-3_1_1+compact.tar.xz", vs.flavor_asset("unidic-cwj"))
      assert.are.equal("jumandic-mecab-7_0.tar.xz", vs.flavor_asset("jumandic"))
    end)

    it("errors on an unknown flavor", function()
      assert.has_error(function()
        vs.flavor_asset("unidic-jawiki")
      end)
    end)
  end)

  describe("steps()", function()
    it("builds the download / extract / build pipeline", function()
      local steps = vs.steps(tmp_root, { flavor = "ipadic", version = "v0.5.2" })
      assert.are.equal(5, #steps)

      -- ソースのダウンロード: GitHub の tarball URL
      assert.are.equal(
        "https://github.com/daac-tools/vibrato/archive/refs/tags/v0.5.2.tar.gz",
        steps[1].cmd[#steps[1].cmd]
      )
      assert.is_truthy(vim.tbl_contains(steps[1].cmd, tmp_root .. "/tmp/vibrato-v0.5.2.tar.gz"))

      -- 展開 → cargo ビルド (cwd は展開先)
      assert.are.same(
        { "tar", "xzf", tmp_root .. "/tmp/vibrato-v0.5.2.tar.gz", "-C", tmp_root .. "/tmp" },
        steps[2].cmd
      )
      assert.are.same({ "cargo", "build", "--release", "-p", "tokenize" }, steps[3].cmd)
      assert.are.equal(tmp_root .. "/tmp/vibrato-0.5.2", steps[3].cwd)

      -- 辞書のダウンロード: v0.5.0 リリースのアセット
      assert.are.equal(
        "https://github.com/daac-tools/vibrato/releases/download/v0.5.0/ipadic-mecab-2_7_0.tar.xz",
        steps[4].cmd[#steps[4].cmd]
      )
      -- 辞書は tar.xz なので xJf
      assert.are.same(
        { "tar", "xJf", tmp_root .. "/tmp/ipadic-mecab-2_7_0.tar.xz", "-C", tmp_root .. "/tmp" },
        steps[5].cmd
      )
    end)
  end)

  describe("run()", function()
    it("installs, writes the manifest and places the artifacts", function()
      make_fake_artifacts("ipadic")
      mock_system_success()

      local done
      local started = vs.run(
        { root = tmp_root, flavor = "ipadic", version = "v0.5.2" },
        function(manifest)
          done = manifest
        end
      )
      assert.is_true(started)

      local ok = vim.wait(2000, function()
        return done ~= nil
      end)
      assert.is_true(ok)

      -- 成果物が配置され、tmp は掃除される
      assert.is_truthy(vim.fn.filereadable(tmp_root .. "/bin/tokenize") == 1)
      assert.is_truthy(vim.fn.filereadable(tmp_root .. "/dict/system.dic.zst") == 1)
      assert.is_false(vim.fn.isdirectory(tmp_root .. "/tmp") == 1)

      -- manifest の内容
      assert.are.equal("v0.5.2", done.version)
      assert.are.equal("ipadic", done.flavor)
      assert.are.equal(tmp_root .. "/bin/tokenize", done.cmd)
      assert.are.equal(tmp_root .. "/dict/system.dic.zst", done.dict)

      -- 実行された外部コマンドの先頭はソースダウンロード
      assert.are.equal(5, #system_calls)

      -- status() が導入済みを報告する
      assert.is_truthy(vs.status():find("v0%.5%.2"))
    end)

    it("skips when already installed (on_done still runs)", function()
      make_fake_artifacts("ipadic")
      mock_system_success()
      vs.run({ root = tmp_root, flavor = "ipadic", version = "v0.5.2" })
      assert.is_true(vim.wait(2000, function()
        return vim.fn.filereadable(tmp_root .. "/manifest.json") == 1
      end))

      system_calls = {}
      local done
      local started = vs.run({ root = tmp_root }, function(manifest)
        done = manifest
      end)
      assert.is_false(started) -- 再実行はしない
      assert.is_truthy(done) -- が manifest は返る
      assert.are.equal(0, #system_calls)
    end)

    it("reinstalls with force", function()
      make_fake_artifacts("ipadic")
      mock_system_success()
      vs.run({ root = tmp_root, flavor = "ipadic", version = "v0.5.2" })
      assert.is_true(vim.wait(2000, function()
        return vim.fn.filereadable(tmp_root .. "/manifest.json") == 1
      end))

      system_calls = {}
      vs.run({ root = tmp_root, flavor = "ipadic", version = "v0.5.2", force = true })
      assert.is_true(vim.wait(2000, function()
        return #system_calls == 5
      end))
    end)

    it("reports an error when a step fails", function()
      -- luacheck: ignore 122
      vim.system = function(cmd, sys_opts, cb)
        system_calls[#system_calls + 1] = { cmd = cmd }
        cb({ code = 101, stdout = "", stderr = "boom" })
      end

      local started = vs.run({ root = tmp_root, flavor = "ipadic", version = "v0.5.2" })
      assert.is_true(started)
      assert.is_true(vim.wait(2000, function()
        return vs._running == nil
      end))
      assert.is_truthy(vim.fn.filereadable(tmp_root .. "/manifest.json") ~= 1)
    end)

    it("refuses to start when dependencies are missing", function()
      local real_deps = vs.missing_deps
      vs.missing_deps = function()
        return { "cargo" }
      end
      local started = vs.run({ root = tmp_root, flavor = "ipadic", version = "v0.5.2" })
      vs.missing_deps = real_deps
      assert.is_false(started)
      assert.are.equal(0, #system_calls)
    end)
  end)

  describe("vibrato.auto_setup", function()
    it("defaults to a 3 second delay", function()
      config.resolve_data({})
      assert.are.equal(3000, config.DATA.vibrato.auto_setup_delay)
    end)

    it("does nothing when disabled (default)", function()
      config.resolve_data({ vibrato = { dict = "/custom/system.dic.zst" } })
      assert.are.equal("/custom/system.dic.zst", config.DATA.vibrato.dict)
      assert.are.equal("vibrato", config.DATA.vibrato.cmd)
      assert.is_false(config.consume_auto_setup_needed())
    end)
    it("disables the backend and marks setup pending when not installed", function()
      config.resolve_data({ vibrato = { auto_setup = true } })
      assert.are.equal("", config.DATA.vibrato.dict)
      assert.is_false(config.use_vibrato())
      assert.is_true(config.consume_auto_setup_needed())
      -- フラグは消費される
      assert.is_false(config.consume_auto_setup_needed())
    end)

    it("resolves to the managed install when the manifest exists", function()
      make_fake_artifacts("ipadic")
      mock_system_success()
      vs.run({ root = tmp_root, flavor = "ipadic", version = "v0.5.2" })
      assert.is_true(vim.wait(2000, function()
        return vim.fn.filereadable(tmp_root .. "/manifest.json") == 1
      end))

      config.resolve_data({ vibrato = { auto_setup = true } })
      assert.are.equal(tmp_root .. "/bin/tokenize", config.DATA.vibrato.cmd)
      assert.are.equal(tmp_root .. "/dict/system.dic.zst", config.DATA.vibrato.dict)
      assert.is_true(config.use_vibrato())
      assert.is_false(config.consume_auto_setup_needed())
    end)

    it("does not start before auto_setup_delay elapses", function()
      local bunsetsu = require("bunsetsu")
      bunsetsu.setup({ vibrato = { auto_setup = true, auto_setup_delay = 10000 } })
      vim.wait(100)
      assert.is_nil(vs._running) -- まだ始まっていない
    end)

    it("triggers the setup from bunsetsu.setup() after the delay", function()
      make_fake_artifacts("ipadic")
      mock_system_success()
      local bunsetsu = require("bunsetsu")
      bunsetsu.setup({ vibrato = { auto_setup = true, auto_setup_delay = 10 } })
      local ok = vim.wait(2000, function()
        return vim.fn.filereadable(tmp_root .. "/manifest.json") == 1
          and config.DATA.vibrato.dict == tmp_root .. "/dict/system.dic.zst"
      end)
      assert.is_true(ok)
      assert.is_true(config.use_vibrato())
    end)

    it("falls back to TinySegmenter when the manifest points at deleted files", function()
      make_fake_artifacts("ipadic")
      mock_system_success()
      vs.run({ root = tmp_root, flavor = "ipadic", version = "v0.5.2" })
      assert.is_true(vim.wait(2000, function()
        return vim.fn.filereadable(tmp_root .. "/manifest.json") == 1
      end))
      -- 辞書を消す → manifest は無効扱い
      vim.fn.delete(tmp_root .. "/dict/system.dic.zst")

      config.resolve_data({ vibrato = { auto_setup = true } })
      assert.are.equal("", config.DATA.vibrato.dict)
      assert.is_false(config.use_vibrato())
    end)
  end)

  describe("apply_vibrato_manifest()", function()
    it("switches the backend to the installed paths", function()
      config.apply_vibrato_manifest({
        version = "v0.5.2",
        flavor = "ipadic",
        cmd = "/opt/bunsetsu/tokenize",
        dict = "/opt/bunsetsu/system.dic.zst",
        installed_at = "2026-09-17T00:00:00Z",
      })
      assert.are.equal("/opt/bunsetsu/tokenize", config.DATA.vibrato.cmd)
      assert.are.equal("/opt/bunsetsu/system.dic.zst", config.DATA.vibrato.dict)
      assert.is_true(config.use_vibrato())
    end)
  end)
end)
