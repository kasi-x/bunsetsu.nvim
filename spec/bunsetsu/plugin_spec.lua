describe("plugin/bunsetsu.lua", function()
  it("defines the :BunsetsuSplit command", function()
    -- exists() はコマンドに対して 2 を返すことがある
    assert.is_true(vim.fn.exists(":BunsetsuSplit") > 0)
  end)
end)
