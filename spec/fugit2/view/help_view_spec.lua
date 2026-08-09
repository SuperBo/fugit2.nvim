local HelpView = require "fugit2.view.components.help_view"

local ns_id = vim.api.nvim_create_namespace "fugit2_test_help"

---@param entries Fugit2HelpEntry[]
---@return string[]
local function render_lines(entries)
  local view = HelpView(ns_id, "File Tree", entries)
  return vim.tbl_map(function(line)
    return line:content()
  end, view._lines)
end

describe("HelpView", function()
  describe("_build_lines", function()
    it("renders empty list", function()
      local lines = render_lines {}
      assert.are.same({}, lines)
    end)

    it("renders single entry with key and desc", function()
      local lines = render_lines {
        { keys = "s", desc = "Stage file" },
      }

      assert.are.equal(1, #lines)
      assert.is_true(lines[1]:find "s" ~= nil)
      assert.is_true(lines[1]:find "Stage file" ~= nil)
    end)

    it("renders multiple entries", function()
      local lines = render_lines {
        { keys = "s", desc = "Stage file" },
        { keys = "u", desc = "Unstage file" },
        { keys = "D / x", desc = "Discard changes" },
      }

      assert.are.equal(3, #lines)
      assert.is_true(lines[1]:find "Stage file" ~= nil)
      assert.is_true(lines[2]:find "Unstage file" ~= nil)
      assert.is_true(lines[3]:find "Discard changes" ~= nil)
    end)

    it("pads keys for aligned descriptions", function()
      local lines = render_lines {
        { keys = "s", desc = "Stage" },
        { keys = "D / x", desc = "Discard" },
      }

      local stage_line = vim.tbl_filter(function(l)
        return l:find "Stage" ~= nil
      end, lines)
      local discard_line = vim.tbl_filter(function(l)
        return l:find "Discard" ~= nil
      end, lines)

      assert.are.equal(1, #stage_line)
      assert.are.equal(1, #discard_line)
      -- "D / x" (5) is longer than "s" (1), so both are padded to width 5
      assert.are.equal(5 + 2, #stage_line[1] - #"Stage")
      assert.are.equal(5 + 2, #discard_line[1] - #"Discard")
    end)

    it("renders disabled key placeholder", function()
      local lines = render_lines {
        { keys = "", desc = "No binding" },
      }

      assert.are.equal(1, #lines)
      assert.is_true(lines[1]:find "<disabled>" ~= nil)
    end)
  end)

  describe("close", function()
    it("is safe when popup not mounted", function()
      local view = HelpView(ns_id, "File Tree", { { keys = "s", desc = "Stage" } })
      -- should not error
      assert.has_no.errors(function()
        view:close()
      end)
    end)
  end)
end)
