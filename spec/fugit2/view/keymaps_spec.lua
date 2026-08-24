local keymaps = require "fugit2.view.keymaps"

local ALL_GROUPS = {
  "file_tree",
  "commit_log",
  "patch_unstaged",
  "patch_staged",
  "rebase",
  "graph_log",
  "graph_branch",
  "graph_select",
  "diff",
  "stash_list",
  "pick",
  "input",
  "confirm",
  "blame",
  "blame_file",
  "blame_popup",
  "patch",
}

describe("keymaps", function()
  describe("defaults", function()
    it("defines all view groups", function()
      for _, group in ipairs(ALL_GROUPS) do
        assert.is_not_nil(keymaps.defaults[group], "missing group: " .. group)
      end
    end)

    it("every def has keys and desc", function()
      for group, defs in pairs(keymaps.defaults) do
        for action, def in pairs(defs) do
          assert.is_not_nil(def.keys, string.format("%s.%s missing keys", group, action))
          assert.is_not_nil(def.desc, string.format("%s.%s missing desc", group, action))
          assert.is_true(def.mode == nil or def.mode == "n" or def.mode == "v" or def.mode == "i")
        end
      end
    end)

    it("file_tree menu actions exist", function()
      local file_tree = keymaps.defaults.file_tree
      assert.are.equal("c", file_tree.menu_commit.keys)
      assert.are.equal("A", file_tree.menu_cherry_pick.keys)
      assert.are.equal("z", file_tree.menu_stash.keys)
      assert.are.equal("r", file_tree.menu_rebase.keys)
    end)
  end)

  describe("get", function()
    it("returns def for known action", function()
      local def = keymaps.get("file_tree", "stage_file")
      assert.are.equal("s", def.keys)
      assert.is_not_nil(def.desc)
    end)

    it("returns nil for unknown action", function()
      assert.is_nil(keymaps.get("file_tree", "nope"))
    end)

    it("returns nil for unknown group", function()
      assert.is_nil(keymaps.get("nope", "stage_file"))
    end)
  end)

  describe("resolve_keys", function()
    it("returns default when no user override", function()
      assert.are.equal("s", keymaps.resolve_keys("file_tree", "stage_file", {}))
    end)

    it("returns user override", function()
      assert.are.equal("S", keymaps.resolve_keys("file_tree", "stage_file", { stage_file = "S" }))
    end)

    it("returns table user override", function()
      local keys = keymaps.resolve_keys("file_tree", "discard", { discard = { "X", "Y" } })
      assert.are.same({ "X", "Y" }, keys)
    end)

    it("returns false when disabled", function()
      assert.are.equal(false, keymaps.resolve_keys("file_tree", "stage_file", { stage_file = false }))
    end)

    it("returns empty string when disabled via empty string", function()
      assert.are.equal("", keymaps.resolve_keys("file_tree", "stage_file", { stage_file = "" }))
    end)

    it("returns nil for unknown action", function()
      assert.is_nil(keymaps.resolve_keys("file_tree", "nope", {}))
    end)
  end)

  describe("bind", function()
    local calls = {}

    ---@type table
    local mock_view = {}

    local function reset()
      calls = {}
      mock_view = {
        map = function(_, mode, keys, handler, opts)
          calls[#calls + 1] = { mode = mode, keys = keys, handler = handler, opts = opts }
        end,
      }
    end

    before_each(reset)

    it("binds all handlers with defaults", function()
      local handlers = {
        stage_file = function() end,
        unstage_file = function() end,
      }
      keymaps.bind(mock_view, "file_tree", handlers)

      local stage = vim.tbl_filter(function(call)
        return call.keys == "s"
      end, calls)
      assert.are.equal(1, #stage)
      assert.are.equal("n", stage[1].mode)
    end)

    it("binds user overrides instead of defaults", function()
      local handlers = {
        stage_file = function() end,
      }
      keymaps.bind(mock_view, "file_tree", handlers, { stage_file = "S" })

      local stage = vim.tbl_filter(function(call)
        return call.keys == "S"
      end, calls)
      assert.are.equal(1, #stage)
      local default_stage = vim.tbl_filter(function(call)
        return call.keys == "s"
      end, calls)
      assert.are.equal(0, #default_stage)
    end)

    it("skips actions disabled with false", function()
      local handlers = {
        stage_file = function() end,
      }
      keymaps.bind(mock_view, "file_tree", handlers, { stage_file = false })
      assert.are.equal(0, #calls)
    end)

    it("binds no-op when handler is empty string", function()
      local handlers = {
        focus_commit_log_disable = "",
      }
      keymaps.bind(mock_view, "file_tree", handlers)
      assert.are.equal(1, #calls)
      assert.are.equal("", calls[1].handler)
    end)

    it("skips actions without handlers", function()
      local handlers = {}
      keymaps.bind(mock_view, "file_tree", handlers, {})
      assert.are.equal(0, #calls)
    end)

    it("does nothing for unknown group", function()
      keymaps.bind(mock_view, "nope", {})
      assert.are.equal(0, #calls)
    end)

    it("binds visual mode actions with mode v", function()
      local handlers = {
        stage_visual = function() end,
      }
      keymaps.bind(mock_view, "file_tree", handlers, {})
      local vis = vim.tbl_filter(function(call)
        return call.mode == "v"
      end, calls)
      assert.are.equal(1, #vis)
      assert.are.equal("s", vis[1].keys)
    end)

    it("binds insert mode actions with mode i", function()
      local handlers = {
        exit_insert = function() end,
      }
      keymaps.bind(mock_view, "file_tree", handlers, {})
      local ins = vim.tbl_filter(function(call)
        return call.mode == "i"
      end, calls)
      assert.are.equal(1, #ins)
    end)
  end)

  describe("bind_buf", function()
    local calls = {}

    local function reset()
      calls = {}
      local keymap = require "nui.utils.keymap"
      keymap.set = function(bufnr, mode, keys, handler, opts)
        calls[#calls + 1] = { mode = mode, keys = keys, handler = handler, opts = opts }
      end
    end

    before_each(reset)

    it("delegates to nui keymap.set", function()
      local handlers = {
        exit = function() end,
      }
      keymaps.bind_buf(1, "blame", handlers, {})
      assert.are.equal(1, #calls)
      assert.are.equal("n", calls[1].mode)
      assert.are.same({ "q", "<esc>" }, calls[1].keys)
    end)

    it("applies user overrides", function()
      local handlers = {
        exit = function() end,
      }
      keymaps.bind_buf(1, "blame", handlers, { exit = "Q" })
      assert.are.equal(1, #calls)
      assert.are.equal("Q", calls[1].keys)
    end)
  end)

  describe("defs", function()
    it("returns group defs", function()
      assert.is_not_nil(keymaps.defs "file_tree")
      assert.are.equal("s", keymaps.defs("file_tree").stage_file.keys)
    end)

    it("returns nil for unknown group", function()
      assert.is_nil(keymaps.defs "nope")
    end)
  end)

  describe("help_entries", function()
    it("returns an entry per action", function()
      local entries = keymaps.help_entries("file_tree", {})
      assert.is_true(#entries > 0)
      for _, e in ipairs(entries) do
        assert.is_not_nil(e.keys)
        assert.is_not_nil(e.desc)
      end
    end)

    it("joins multiple keys with /", function()
      local entries = keymaps.help_entries("file_tree", {})
      local discard
      for _, e in ipairs(entries) do
        if e.desc == "Discard changes" then
          discard = e
        end
      end
      assert.is_not_nil(discard)
      assert.are.equal("D / x", discard.keys)
    end)

    it("reflects user overrides", function()
      local entries = keymaps.help_entries("file_tree", { stage_file = "S" })
      local stage
      for _, e in ipairs(entries) do
        if e.desc == "Stage file" then
          stage = e
        end
      end
      assert.is_not_nil(stage)
      assert.are.equal("S", stage.keys)
    end)

    it("omits disabled actions", function()
      local entries = keymaps.help_entries("file_tree", { stage_file = false })
      local stage = vim.tbl_filter(function(e)
        return e.desc == "Stage file"
      end, entries)
      assert.are.equal(0, #stage)
    end)

    it("includes no-op actions", function()
      local entries = keymaps.help_entries("file_tree", {})
      local disable = vim.tbl_filter(function(e)
        return e.desc == "No-op: disable mirror pane move"
      end, entries)
      assert.are.equal(1, #disable)
    end)

    it("only includes actions with active handlers", function()
      local handlers = {
        help = function() end,
        start = function() end,
      }
      local entries = keymaps.help_entries("rebase", {}, handlers)
      local descriptions = vim.tbl_map(function(e)
        return e.desc
      end, entries)

      assert.are.same({ "Show keymap help", "Start rebase" }, descriptions)
    end)

    it("returns empty for unknown group", function()
      assert.are.same({}, keymaps.help_entries "nope")
    end)

    it("sorts entries by action name", function()
      local entries = keymaps.help_entries("stash_list", {})
      local keys = vim.tbl_map(function(e)
        return e.desc
      end, entries)
      local sorted = vim.deepcopy(keys)
      table.sort(sorted)
      assert.are.same(sorted, keys)
    end)
  end)
end)
