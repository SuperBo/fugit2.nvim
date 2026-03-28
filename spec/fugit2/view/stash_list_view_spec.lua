local StashListView = require "fugit2.view.components.stash_list_view"

local ns_id = vim.api.nvim_create_namespace "fugit2_test_stash"

---@param entries StashEntry[]
---@return string[]
local function render_lines(entries)
  local view = StashListView(ns_id, entries)
  return vim.tbl_map(function(line)
    return line:content()
  end, view._lines)
end

describe("StashListView", function()
  describe("_build_lines", function()
    it("renders empty list", function()
      local lines = render_lines {}
      assert.are.same({}, lines)
    end)

    it("renders single stash entry", function()
      local entries = {
        { index = 0, message = "WIP on main: fix bug", oid = nil },
      }
      local lines = render_lines(entries)

      assert.are.equal(1, #lines)
      assert.is_true(lines[1]:find "stash@{0}" ~= nil)
      assert.is_true(lines[1]:find "WIP on main: fix bug" ~= nil)
    end)

    it("renders multiple stash entries", function()
      local entries = {
        { index = 0, message = "WIP on main: latest", oid = nil },
        { index = 1, message = "experiment: try layout", oid = nil },
        { index = 2, message = "half-done oauth", oid = nil },
      }
      local lines = render_lines(entries)

      assert.are.equal(3, #lines)
      assert.is_true(lines[1]:find "stash@{0}" ~= nil)
      assert.is_true(lines[2]:find "stash@{1}" ~= nil)
      assert.is_true(lines[3]:find "stash@{2}" ~= nil)
      assert.is_true(lines[1]:find "latest" ~= nil)
      assert.is_true(lines[2]:find "try layout" ~= nil)
      assert.is_true(lines[3]:find "oauth" ~= nil)
    end)

    it("handles empty message", function()
      local entries = {
        { index = 0, message = "", oid = nil },
      }
      local lines = render_lines(entries)

      assert.are.equal(1, #lines)
      assert.is_true(lines[1]:find "stash@{0}" ~= nil)
    end)
  end)

  describe("get_entry", function()
    it("returns entry by line number", function()
      local entries = {
        { index = 0, message = "first", oid = nil },
        { index = 1, message = "second", oid = nil },
        { index = 2, message = "third", oid = nil },
      }
      local view = StashListView(ns_id, entries)

      -- 1-based line numbers map directly to entries
      assert.are.equal("first", view:get_entry(1).message)
      assert.are.equal("second", view:get_entry(2).message)
      assert.are.equal("third", view:get_entry(3).message)
    end)

    it("returns nil for out of range line number", function()
      local entries = {
        { index = 0, message = "only", oid = nil },
      }
      local view = StashListView(ns_id, entries)

      assert.is_nil(view:get_entry(0))
      assert.is_nil(view:get_entry(2))
    end)

    it("returns nil when no winid and no linenr", function()
      local entries = {
        { index = 0, message = "test", oid = nil },
      }
      local view = StashListView(ns_id, entries)

      -- popup not mounted, so winid is nil
      assert.is_nil(view:get_entry())
    end)
  end)

  describe("update", function()
    it("replaces entries and rebuilds lines", function()
      local entries = {
        { index = 0, message = "old", oid = nil },
      }
      local view = StashListView(ns_id, entries)
      assert.are.equal(1, #view._lines)

      local new_entries = {
        { index = 0, message = "new first", oid = nil },
        { index = 1, message = "new second", oid = nil },
      }
      -- update calls _build_lines internally but also calls popup:update_layout
      -- which requires a mounted popup; test the data layer directly
      view._entries = new_entries
      view:_build_lines()

      assert.are.equal(2, #view._lines)
      assert.is_true(view._lines[1]:content():find "new first" ~= nil)
      assert.is_true(view._lines[2]:content():find "new second" ~= nil)
    end)

    it("handles update to empty list", function()
      local entries = {
        { index = 0, message = "will be dropped", oid = nil },
      }
      local view = StashListView(ns_id, entries)

      view._entries = {}
      view:_build_lines()

      assert.are.equal(0, #view._lines)
    end)
  end)

  describe("on_action", function()
    it("stores action callback", function()
      local entries = {
        { index = 0, message = "test", oid = nil },
      }
      local view = StashListView(ns_id, entries)
      local called = false

      view:on_action(function()
        called = true
      end)

      assert.is_not_nil(view._action_fn)
      view._action_fn("apply", entries[1])
      assert.is_true(called)
    end)

    it("passes action and entry to callback", function()
      local entries = {
        { index = 0, message = "first", oid = nil },
        { index = 1, message = "second", oid = nil },
      }
      local view = StashListView(ns_id, entries)
      local received_action, received_entry

      view:on_action(function(action, entry)
        received_action = action
        received_entry = entry
      end)

      view._action_fn("drop", entries[2])
      assert.are.equal("drop", received_action)
      assert.are.equal(1, received_entry.index)
      assert.are.equal("second", received_entry.message)
    end)
  end)
end)
