describe("plugin/bunsetsu.lua", function()
  it("defines the :BunsetsuSplit command", function()
    -- exists() はコマンドに対して 2 を返すことがある
    assert.is_true(vim.fn.exists(":BunsetsuSplit") > 0)
  end)

  it("splits japanese lines, and keeps ascii/empty lines intact", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "これは文章です。",
      "hello world",
      "",
    })
    vim.cmd("1,3BunsetsuSplit")
    assert.are.same({
      "これは 文章です。",
      "hello world",
      "",
    }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)
end)
