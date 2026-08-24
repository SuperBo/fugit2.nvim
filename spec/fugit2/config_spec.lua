local function fresh_config()
  package.loaded["fugit2.config"] = nil
  return require "fugit2.config"
end

describe("config", function()
  describe("merge", function()
    it("merges partial args into defaults", function()
      local config = fresh_config()
      local cfg = config.merge { width = 120 }
      assert.are.equal(120, cfg.width)
      assert.are.equal("60%", cfg.height)
    end)

    it("deep merges nested tables", function()
      local config = fresh_config()
      local cfg = config.merge { file_tree_maps = { menu = { commit = "C" } } }
      assert.are.equal("C", cfg.file_tree_maps.menu.commit)
      assert.are.equal("z", cfg.file_tree_maps.menu.stash)
    end)

    it("translates legacy file_tree_maps.menu into keymaps.file_tree.menu_*", function()
      local config = fresh_config()
      local cfg = config.merge {
        file_tree_maps = { menu = { commit = "C", stash = "Z" } },
      }
      assert.are.equal("C", cfg.keymaps.file_tree.menu_commit)
      assert.are.equal("Z", cfg.keymaps.file_tree.menu_stash)
    end)

    it("does not translate defaults (they live in the keymap registry)", function()
      local config = fresh_config()
      local cfg = config.merge {}
      assert.is_nil(cfg.keymaps.file_tree.menu_commit)
    end)

    it("new keymaps take precedence over legacy file_tree_maps", function()
      local config = fresh_config()
      local cfg = config.merge {
        file_tree_maps = { menu = { commit = "C" } },
        keymaps = { file_tree = { menu_commit = "X" } },
      }
      assert.are.equal("X", cfg.keymaps.file_tree.menu_commit)
    end)

    it("keeps user keymaps groups intact", function()
      local config = fresh_config()
      local cfg = config.merge {
        keymaps = {
          file_tree = { stage_file = "S", unstage_file = false },
          rebase = { drop = { "x", "d" } },
        },
      }
      assert.are.equal("S", cfg.keymaps.file_tree.stage_file)
      assert.are.equal(false, cfg.keymaps.file_tree.unstage_file)
      assert.are.same({ "x", "d" }, cfg.keymaps.rebase.drop)
    end)

    it("always populates keymaps.file_tree", function()
      local config = fresh_config()
      local cfg = config.merge {}
      assert.is_not_nil(cfg.keymaps)
      assert.is_not_nil(cfg.keymaps.file_tree)
    end)
  end)
end)
