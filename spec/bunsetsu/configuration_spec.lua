describe("bunsetsu.configuration", function()
  local config = require("bunsetsu._core.configuration")

  describe("initialize_data_if_needed()", function()
    it("fills DATA with defaults", function()
      config.initialize_data_if_needed()
      config.resolve_data()
      assert.are.equal("knbc_bunsetu", config.DATA.model)
      assert.are.equal("[?!、。]", config.DATA.splitpat)
      assert.are.equal(" ", config.DATA.splitsep)
      assert.are.equal(50, config.DATA.debounce)
      assert.are.equal("vibrato", config.DATA.vibrato.cmd)
      assert.are.equal("", config.DATA.vibrato.dict)
      assert.are.equal("predict", config.DATA.vaporetto.cmd)
      assert.are.equal("", config.DATA.vaporetto.model)
      assert.are.equal("", config.DATA.lemma.dict_path)
      assert.is_false(config.DATA.highlight.enabled)
    end)
  end)

  describe("resolve_data()", function()
    after_each(function()
      -- 後続の spec に設定が漏れないよう既定値に戻す
      config.resolve_data({
        model = "knbc_bunsetu",
        splitpat = "[?!、。]",
        splitsep = " ",
        vibrato = { dict = "" },
        vaporetto = { model = "" },
      })
      vim.g.bunsetsu_configuration = nil
    end)

    it("merges overrides into DATA", function()
      config.resolve_data({ model = "rwcp" })
      assert.are.equal("rwcp", config.DATA.model)
      config.resolve_data()
      -- 引数なしの呼び出しでも上書きは維持される
      assert.are.equal("rwcp", config.DATA.model)
    end)

    it("reflects vim.g.bunsetsu_configuration set after load", function()
      vim.g.bunsetsu_configuration = { splitsep = "|" }
      config.resolve_data()
      assert.are.equal("|", config.DATA.splitsep)
    end)

    it("gives precedence to explicit data over vim.g", function()
      vim.g.bunsetsu_configuration = { splitsep = "|" }
      config.resolve_data({ splitsep = "-" })
      assert.are.equal("-", config.DATA.splitsep)
    end)

    it("toggles vibrato backend via nested table", function()
      config.resolve_data({ vibrato = { dict = "/tmp/fake.dic" } })
      local full = require("bunsetsu._commands.full")
      assert.is_true(full.use_vibrato())
      config.resolve_data({ vibrato = { dict = "" } })
      assert.is_false(full.use_vibrato())
    end)
  end)
end)
