describe("documentation consistency", function()
  it("resolves every |reference| in the help to a defined tag", function()
    local defined = {}
    for _, line in ipairs(vim.fn.readfile("doc/tags")) do
      defined[vim.split(line, "\t", { plain = true })[1]] = true
    end
    -- Neovim 組み込みタグなど、本リポジトリの tags に無い参照の許可リスト
    local allowed = { cword = true }

    local refs = {}
    for _, line in ipairs(vim.fn.readfile("doc/bunsetsu.txt")) do
      for ref in line:gmatch("|([%w:.-]+)|") do
        refs[#refs + 1] = ref
      end
    end
    assert.is_true(#refs >= 10) -- 目次ぶんの参照は必ずある

    for _, ref in ipairs(refs) do
      if not defined[ref] and not allowed[ref] then
        error(("undefined help tag: |%s|"):format(ref))
      end
    end
  end)

  it("uses the same repository name in README and rockspec", function()
    local readme = table.concat(vim.fn.readfile("README.md"), "\n")
    assert.is_truthy(readme:find("kasi%-x/bunsetsu%.nvim"))

    local rockspec = table.concat(vim.fn.readfile("bunsetsu-scm-1.rockspec"), "\n")
    assert.is_truthy(rockspec:find("github%.com/kasi%-x/bunsetsu%.nvim"))
  end)
end)
