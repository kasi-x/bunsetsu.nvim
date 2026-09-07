describe("bunsetsu.models (model registry)", function()
  local models = require("bunsetsu._core.models")

  describe("list()", function()
    it("registers the four bundled TinySegmenter models", function()
      local names = models.list()
      assert.are.same({ "jeita", "knbc_bunsetu", "rwcp", "wpci_bunsetu" }, names)
    end)
  end)

  describe("get()", function()
    it("returns a segmentation function for known models", function()
      local fn = models.get("knbc_bunsetu")
      assert.is_function(fn)
      -- TinySegmenter (knbc_bunsetu) は文節区切りを返す
      assert.are.same({ "これは", "文章です。" }, fn("これは文章です。"))
    end)

    it("returns nil for unknown models", function()
      assert.is_nil(models.get("unknown_model"))
    end)
  end)

  describe("splitpat()", function()
    it("returns nil for models without a model-specific splitpat", function()
      assert.is_nil(models.splitpat("knbc_bunsetu"))
      assert.is_nil(models.splitpat("unknown_model"))
    end)
  end)

  describe("register()", function()
    local custom_called

    after_each(function()
      -- 独自モデルはレジストリから消せないので、同名で上書きしておく
      models.register("custom_test", function()
        return {}
      end)
    end)

    it("allows registering a custom model", function()
      models.register("custom_test", function(input)
        custom_called = input
        return { input }
      end)
      local fn = models.get("custom_test")
      assert.is_function(fn)
      assert.are.same({ "abc" }, fn("abc"))
      assert.are.equal("abc", custom_called)
    end)
  end)
end)
