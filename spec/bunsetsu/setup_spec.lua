describe("bunsetsu.setup() (user-facing integration)", function()
  local bunsetsu = require("bunsetsu")
  local full = require("bunsetsu._commands.full")

  before_each(function()
    full.invalidate()
  end)

  it("registers the bookkeeping autocmds", function()
    bunsetsu.setup({})
    local autocmds = vim.api.nvim_get_autocmds({ group = "bunsetsu" })
    assert.is_true(#autocmds >= 4)
    local events = {}
    for _, au in ipairs(autocmds) do
      if type(au.event) == "table" then
        for _, ev in ipairs(au.event) do
          events[ev] = true
        end
      else
        events[au.event] = true
      end
    end
    assert.is_truthy(events.TextChanged)
    assert.is_truthy(events.BufReadPost)
    assert.is_truthy(events.BufWipeout)
  end)

  it("refreshes edited lines through the debounce path (TinySegmenter)", function()
    bunsetsu.setup({})
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは文章です。" })
    vim.api.nvim_exec_autocmds("BufReadPost", { buffer = 0 })

    -- 編集 → TextChanged → debounce (既定 50ms) 経由で再分割される
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "これは編集されました。" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })

    local ok = vim.wait(500, function()
      local texts = vim.tbl_map(function(s)
        return s.text
      end, bunsetsu.full_segments())
      return table.concat(texts):find("編集") ~= nil
    end)
    assert.is_true(ok)
  end)

  it("merges setup() options into the configuration (tiered options)", function()
    local config = require("bunsetsu._core.configuration")
    bunsetsu.setup({
      debounce = 123,
      sentence = { extra_end_chars = "♪" },
      highlight = { enabled = true },
    })
    assert.are.equal(123, config.DATA.debounce)
    assert.are.equal("♪", config.DATA.sentence.extra_end_chars)
    assert.is_true(config.DATA.highlight.enabled)
    -- 未指定の既定値は残る
    assert.are.equal(500, config.DATA.jp_scan_lines)
    -- 元に戻す
    bunsetsu.setup({
      debounce = 50,
      sentence = { extra_end_chars = "" },
      highlight = { enabled = false },
    })
  end)

  it("does not error on ascii-only buffers", function()
    bunsetsu.setup({})
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
    vim.api.nvim_exec_autocmds("BufReadPost", { buffer = 0 })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello brave world" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    vim.wait(50)
    assert.are.same({ "hello brave world" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)
end)
