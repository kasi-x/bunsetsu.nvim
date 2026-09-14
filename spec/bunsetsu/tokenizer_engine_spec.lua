-- tokenizer_engine の結合テスト。
-- 偽トークナイザ (shell script) を pty の jobstart で起動し、sync/async の
-- 両パスとブロック組み立て ("eos" 区切り / "line" 区切り) を検証する。

describe("bunsetsu.tokenizer_engine", function()
  local tokenizer_engine = require("bunsetsu._core.tokenizer_engine")

  local tmp_scripts = {}

  ---偽トークナイザの shell script を書き出してパスを返す。
  ---@param body string[]
  ---@return string
  local function write_script(body)
    local path = vim.fn.tempname() .. ".sh"
    vim.fn.writefile({ "#!/bin/sh" }, path)
    vim.fn.writefile(body, path, "a")
    vim.fn.setfperm(path, "rwxr-xr-x")
    tmp_scripts[#tmp_scripts + 1] = path
    return path
  end

  after_each(function()
    for _, path in ipairs(tmp_scripts) do
      os.remove(path)
    end
    tmp_scripts = {}
  end)

  describe("block_mode = eos (vibrato 風)", function()
    local engine
    local script

    before_each(function()
      -- 入力行を MeCab 形式にして返し、EOS でブロックを確定させる偽物
      script = write_script({
        "echo 'Loading the dictionary'",
        "echo 'Ready to tokenize'",
        "while IFS= read -r line; do",
        [[printf '%s\t名詞\tテスト\n' "$line"]],
        "echo EOS",
        "done",
      })
      engine = tokenizer_engine.new({
        build_cmd = function()
          return { "sh", script }
        end,
        classify = function(line)
          if line:find("Ready to tokenize") then
            return "ready"
          elseif line:find("Loading") then
            return "skip"
          elseif line == "EOS" then
            return "eos"
          elseif line:find("\t") then
            return "result"
          end
          return "skip"
        end,
        block_mode = "eos",
      })
    end)

    it("sync_request returns a block of result lines", function()
      local block = engine:sync_request("これはテスト")
      assert.is_not_nil(block)
      assert.are.same({ "これはテスト\t名詞\tテスト" }, block)
    end)

    it("sync_request handles multiple sequential requests", function()
      assert.are.same({ "一\t名詞\tテスト" }, engine:sync_request("一"))
      assert.are.same({ "二\t名詞\tテスト" }, engine:sync_request("二"))
    end)

    it("tokenize_async returns one block per line", function()
      local results
      engine:tokenize_async({
        { lnum = 1, line = "一" },
        { lnum = 2, line = "二" },
      }, function(r)
        results = r
      end)
      assert.is_true(vim.wait(5000, function()
        return results ~= nil
      end))
      assert.are.equal(2, #results)
      -- ブロックは MeCab 形式の出力行 (表層形\t品詞\t読み)
      assert.are.same({ "一\t名詞\tテスト" }, results[1].block)
      assert.are.equal(2, results[2].item.lnum)
      assert.are.same({ "二\t名詞\tテスト" }, results[2].block)
    end)

    it("is_running reflects the sync job", function()
      engine:sync_request("テスト")
      assert.is_true(engine:is_running())
      engine:stop()
      assert.is_false(engine:is_running())
    end)
  end)

  describe("block_mode = line (vaporetto 風)", function()
    local engine
    local script

    before_each(function()
      -- 入力行を "単語/品詞/読み" 形式にして返す偽物 (1 行 1 ブロック)
      script = write_script({
        "echo 'Start tokenization'",
        "echo 'Loading model file'",
        "while IFS= read -r line; do",
        [[printf '%s/名詞/テスト\n' "$line"]],
        "done",
      })
      engine = tokenizer_engine.new({
        build_cmd = function()
          return { "sh", script }
        end,
        classify = function(line)
          if line:find("Start tokenization") then
            return "ready"
          elseif line:find("Loading") or line:find("^Elapsed:") then
            return "skip"
          elseif line ~= "" and line:find("/") then
            return "result"
          end
          return "skip"
        end,
        block_mode = "line",
      })
    end)

    it("sync_request returns each result line as its own block", function()
      assert.are.same({ "一/名詞/テスト" }, engine:sync_request("一"))
      assert.are.same({ "二/名詞/テスト" }, engine:sync_request("二"))
    end)

    it("tokenize_async pairs lines with blocks in order", function()
      local results
      engine:tokenize_async({
        { lnum = 1, line = "一" },
        { lnum = 2, line = "二" },
      }, function(r)
        results = r
      end)
      assert.is_true(vim.wait(5000, function()
        return results ~= nil
      end))
      assert.are.same({ "一/名詞/テスト" }, results[1].block)
      assert.are.same({ "二/名詞/テスト" }, results[2].block)
    end)
  end)
end)
