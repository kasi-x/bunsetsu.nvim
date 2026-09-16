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

    local rockspec = table.concat(vim.fn.readfile("bunsetsu.nvim-scm-1.rockspec"), "\n")
    assert.is_truthy(rockspec:find("github%.com/kasi%-x/bunsetsu%.nvim"))
  end)
end)

describe("configuration option documentation", function()
  local config = require("bunsetsu._core.configuration")

  local function help_config_section()
    local out = {}
    local in_sec = false
    for _, line in ipairs(vim.fn.readfile("doc/bunsetsu.txt")) do
      if line:find("%*bunsetsu%-config%*") then
        in_sec = true
      elseif in_sec and line:find("%*bunsetsu%-spider%*") then
        break
      end
      if in_sec then
        out[#out + 1] = line
      end
    end
    return table.concat(out, "\n")
  end

  local function readme_config_section()
    local out = {}
    local in_sec = false
    for _, line in ipairs(vim.fn.readfile("README.md")) do
      if line == "## Configuration" then
        in_sec = true
      elseif in_sec and line == "### Backends" then
        break
      end
      if in_sec then
        out[#out + 1] = line
      end
    end
    return table.concat(out, "\n")
  end

  it("documents every top-level option in help and README", function()
    config.initialize_data_if_needed()
    config.resolve_data()
    local help_sec, readme_sec = help_config_section(), readme_config_section()
    for _, key in ipairs(vim.tbl_keys(config.DATA)) do
      assert.is_truthy(
        help_sec:find(key, 1, true),
        ("doc/bunsetsu.txt の設定セクションに '%s' がない"):format(key)
      )
      assert.is_truthy(
        readme_sec:find(key, 1, true),
        ("README の Configuration に '%s' がない"):format(key)
      )
    end
  end)

  it("does not document options that no longer exist (help)", function()
    local keys = {}
    config.initialize_data_if_needed()
    config.resolve_data()
    for _, key in ipairs(vim.tbl_keys(config.DATA)) do
      keys[key] = true
    end
    -- 設定セクションのオプション名列 (行頭の lower_snake_case) を抽出
    for _, line in ipairs(vim.split(help_config_section(), "\n", { plain = true })) do
      local name = line:match("^([a-z_]+)%s")
      if name then
        assert.is_truthy(
          keys[name],
          ("doc/bunsetsu.txt が未知のオプション '%s' を記載している"):format(name)
        )
      end
    end
  end)
end)
