local context = require "plenary.context_manager"
local diff = require "fugit2.diff"
local git2 = require "fugit2.git2"


---@param path string
---@return string
local function read_patch_file(path)
  local ret = ""
  context.with(context.open(path, "r"), function(reader)
    ret = reader:read("*all")
  end)
  return ret
end

describe("parse_patch", function()
  local patch = read_patch_file("tests/resources/patch_a.diff")

  it("get correct header", function()
    local patch_item = diff.parse_patch(patch)

    assert.is_not_nil(patch_item.header)
    assert.array(patch_item.header).has.no.holes()
    assert.equals(4, #patch_item.header)
  end)

  it("get correct num hunk", function()
    local patch_item = diff.parse_patch(patch)

    assert.is_not_nil(patch_item.hunks)
    assert.array(patch_item.hunks).has.no.holes()
    assert.equals(4, #patch_item.hunks)
  end)

  it("get correct hunk", function()
    local patch_item = diff.parse_patch(patch)

    assert.is_not_nil(patch_item.hunks)
    assert.is_not_nil(patch_item.hunks[4])

    local hunk = patch_item.hunks[4]

    assert.equals("@@ -149,4 +172,23 @@ function PatchView:unmount()", hunk.header)
    assert.equals(" return PatchView", hunk.lines[#hunk.lines].text)
    assert.equals(" ", hunk.lines[#hunk.lines].c)
    assert.equals(92, hunk.lines[#hunk.lines].linenr)
    assert.equals(23, #hunk.lines)
  end)
end)

describe("partial_patch_from_hunk", function()
  local patch = read_patch_file("tests/resources/patch_a.diff")
  local function read_hunk(idx)
    local patch_item = diff.parse_patch(patch)

    local header = patch_item.header
    local hunk_header = ""
    local hunk_lines = {}

    local hunk = patch_item.hunks[idx]
    if hunk then
      hunk_header = hunk.header
      hunk_lines = vim.tbl_map(function (value)
        return value.text
      end, hunk.lines)
    end

    return header, hunk_header, hunk_lines
  end

  it("creates partial patch", function()
    local header, hunk_header, hunk_lines = read_hunk(1)

    local partial_patch = diff.partial_patch_from_hunk(header, hunk_header, hunk_lines)

    assert.is_not_nil(partial_patch)
    assert.equals("string", type(partial_patch))
    assert.equals([[diff --git a/lua/fugit2/view/components/patch_view.lua b/lua/fugit2/view/components/patch_view.lua
index fd118ca..0167db3 100644
--- a/lua/fugit2/view/components/patch_view.lua
+++ b/lua/fugit2/view/components/patch_view.lua
@@ -50,6 +50,11 @@ function PatchView:init(ns_id, title)
   -- sub components
   self.tree = nil
   self.header = {}
+
+
+  -- keymaps
+  self.popup:map("n", "]", self:next_hunk_handler(), { noremap = true, nowait = true })
+  self.popup:map("n", "[", self:prev_hunk_handler(), { noremap = true, nowait = true })
 end
 
 local function tree_prepare_node(node)
]],
      partial_patch)
  end)

  it("creates partial patch 2", function()
    local header, hunk_header, hunk_lines = read_hunk(4)

    local partial_patch = diff.partial_patch_from_hunk(header, hunk_header, hunk_lines)

    assert.is_not_nil(partial_patch)
    assert.equals("string", type(partial_patch))
    assert.equals([[diff --git a/lua/fugit2/view/components/patch_view.lua b/lua/fugit2/view/components/patch_view.lua
index fd118ca..0167db3 100644
--- a/lua/fugit2/view/components/patch_view.lua
+++ b/lua/fugit2/view/components/patch_view.lua
@@ -149,4 +172,23 @@ function PatchView:unmount()
   return self.popup:unmount()
 end
 
+-- keys handlers
+function PatchView:next_hunk_handler()
+  return function()
+    local node = self.tree:get_node()
+    if node and node.hunk_id then
+      -- TODO
+    end
+  end
+end
+
+function PatchView:prev_hunk_handler()
+  return function()
+    local node = self.tree:get_node()
+    if node and node.hunk_id then
+      -- TODO
+    end
+  end
+end
+
 return PatchView
]],
      partial_patch)
  end)

  it("create valid git2 diff", function()
    local header, hunk_header, hunk_lines = read_hunk(4)

    local partial_patch = diff.partial_patch_from_hunk(header, hunk_header, hunk_lines)

    assert.is_not_nil(partial_patch)

    local diff, err = git2.Diff.from_buffer(partial_patch)

    assert.equals(0, err)
    assert.is_not_nil(diff)
    assert.is_not_nil(diff.diff)
  end)
end)

describe("partial_hunk", function()
  local test_hunk_1 = vim.split([[
@@ -219,7 +232,7 @@ function PatchView:prev_hunk_handler()
       if hunk_idx <= 1 then
         new_row = 1
       else
-        new_row = self._hunks[hunk_idx-1]
+        new_row = self._hunk_offsets[hunk_idx-1]
       end
     end
     vim.api.nvim_win_set_cursor(self.popup.winid, { new_row, col })]],
    "\n", { plain = true, trimempty = true }
  )

  local test_hunk_2 = vim.split([[
@@ -1,3 +1,5 @@
+local utils = require "fugit2.utils"
+
 ---Diff helper module
 ---@module 'Fugit2DiffHelper'
 local M = {}
    ]],
    "\n", { plain = true, trimempty = true }
  )

  local test_hunk_3 = vim.split([[
@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)
 end
 
 
--- Inserts new element into a sorted list, return a sorted list.
----@param lst table
+---Inserts new element into a sorted list, return a sorted list.
+---@generic T
+---@param lst T[]
 ---@param ele number
+---@return T[]
 function M.list_sorted_insert(lst, ele)
   local i = 1
   while i < #lst + 1 and ele > lst[i] do]],
    "\n", { plain = true, trimempty = true }
  )

  local test_hunk_4 = vim.split([[
@@ -320,7 +320,7 @@ function PatchView:prev_hunk_handler()
       if hunk_idx <= 1 then
         new_row = 1
       else
-        new_row = self._hunks[hunk_idx-1]
+        new_row = self._hunk_offsets[hunk_idx-1]
       end
     end
     vim.api.nvim_win_set_cursor(self.popup.winid, { new_row, col })
  ]],
    "\n", { plain = true, trimempty = true }
  )

  it("extracts partial_hunk", function()
    local hunk = {
      old_start = 219,
      old_lines = 7,
      new_start = 232,
      new_lines = 7,
      header = "@@ -219,7 +232,7 @@ function PatchView:prev_hunk_handler()\n"
    }
    local hunk_lines = test_hunk_1

    local _, partial = diff.partial_hunk(hunk, hunk_lines)

    assert.array(partial).has.no.holes()
    assert.equals(#hunk_lines, #partial)
    assert.equals("@@ -219,7 +219,7 @@ function PatchView:prev_hunk_handler()", partial[1])
    assert.equals("       if hunk_idx <= 1 then", partial[2])
  end)

  it("extracts untracked hunk", function()
    local hunk = {
      old_start = 0,
      old_lines = 0,
      new_start = 1,
      new_lines = 10,
      header    = "@@ -0,0 +1,10 @@\n"
    }
    local hunk_lines = vim.split([[
@@ -0,0 +1,10 @@
+{
+    "workspace.library": [
+        "/Users/a/",
+        "/opt/a/",
+        "/Users/",
+        "${3rd}/luv/library",
+        "/nui.nvim/lua"
+    ],
+    "workspace.checkThirdParty": false
+}
    ]], "\n", { plain = true, trimempty = true })

    local _, partial = diff.partial_hunk(hunk, hunk_lines)

    assert.array(partial).has.no.holes()
    assert.equals(#hunk_lines, #partial)
    assert.equals("@@ -0,0 +1,10 @@", partial[1])
  end)


  it("extracts selected partial hunk 1", function()
    local hunk = {
      old_start = 1, old_lines = 3,
      new_start = 1, new_lines = 5,
      header = "@@ -1,3 +1,5 @@\n"
    }
    local hunk_lines = test_hunk_2

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 1, 2, false)

    assert.array(selected).has.no.holes()
    assert.equals("@@ -1,3 +1,4 @@", selected[1])
    assert.equals(" ---Diff helper module", selected[3])
  end)

  it("extracts selected partial hunk 2", function()
    local hunk = {
      old_start = 1, old_lines = 3,
      new_start = 1, new_lines = 5,
      header = "@@ -1,3 +1,5 @@\n"
    }
    local hunk_lines = test_hunk_2

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 1, 3, false)

    assert.array(selected).has.no.holes()
    assert.equals("@@ -1,3 +1,5 @@", selected[1])
    assert.equals("+", selected[3])
  end)


  it("extracts selected partial hunk 3", function()
    local hunk = {
      old_start = 277, old_lines = 9,
      new_start = 277, new_lines = 11,
      header = "@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)\n"
    }
    local hunk_lines = test_hunk_3

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 1, 6, false)

    assert.array(selected).has.no.holes()
    assert.equals(9, #selected)
    assert.equals("@@ -277,8 +277,6 @@ function BitArray:set_k_unset_indices(k)", selected[1])
    assert.equals("   local i = 1", selected[9])
  end)

  it("extracts selected partial hunk 4", function()
    local hunk = {
      old_start = 277, old_lines = 9,
      new_start = 277, new_lines = 11,
      header = "@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)\n"
    }
    local hunk_lines = test_hunk_3

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 7, 10, false)

    assert.is_not_nil(selected)
    assert.array(selected).has.no.holes()
    assert.equals(11, #selected)
    assert.equals("@@ -277,7 +277,10 @@ function BitArray:set_k_unset_indices(k)", selected[1])
    assert.equals("+---@generic T", selected[6])
  end)

  it("extracts selected partial hunk for reverse 1", function()
    local hunk = {
      old_start = 219,
      old_lines = 7,
      new_start = 232,
      new_lines = 7,
      header = "@@ -219,7 +232,7 @@ function PatchView:prev_hunk_handler()\n"
    }
    local hunk_lines = test_hunk_1

    local _, partial = diff.partial_hunk_selected(hunk, hunk_lines, 3, 5, true)

    assert.array(partial).has.no.holes()
    assert.equals(8, #partial)
    assert.equals("@@ -219,7 +219,6 @@ function PatchView:prev_hunk_handler()", partial[1])
    assert.equals("-        new_row = self._hunks[hunk_idx-1]", partial[5])
    assert.equals("         new_row = self._hunk_offsets[hunk_idx-1]", partial[6])
  end)

  it("returns nil for context only selection", function()
    local hunk = {
      old_start = 277, old_lines = 9,
      new_start = 277, new_lines = 11,
      header = "@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)\n"
    }
    local hunk_lines = test_hunk_3

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 1, 3, false)

    assert.is_nil(selected)
  end)

  it("merges 2 partial hunks into one", function()
    local hunk1 = {
      old_start = 1, old_lines = 3,
      new_start = 1, new_lines = 5,
      header = "@@ -1,3 +1,5 @@\n"
    }
    local hunk_lines1 = test_hunk_2
    local hunk2 = {
      old_start = 277, old_lines = 9,
      new_start = 277, new_lines = 11,
      header = "@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)\n"
    }
    local hunk_lines2 = test_hunk_3
    local hunks = { hunk1, hunk2 }
    local hunk_segments = { hunk_lines1, hunk_lines2 }

    local merged = diff.merge_hunks(hunks, hunk_segments)

    assert.is_not_nil(merged)
    assert.array(merged).has.no.holes()
    assert.equals(#hunk_lines1 + #hunk_lines2, #merged)
    assert.equals("@@ -1,3 +1,5 @@", merged[1])
    assert.equals("@@ -277,9 +279,11 @@ function BitArray:set_k_unset_indices(k)", merged[#hunk_lines1+1])
  end)

  it("merges 3 partial hunks into one", function()
    local hunk1 = {
      old_start = 1, old_lines = 3,
      new_start = 1, new_lines = 5,
      header = "@@ -1,3 +1,5 @@\n"
    }
    local hunk_lines1 = test_hunk_2
    local hunk2 = {
      old_start = 277, old_lines = 9,
      new_start = 277, new_lines = 11,
      header = "@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)\n"
    }
    local hunk_lines2 = test_hunk_3
    local hunk3 = {
      old_start = 320, old_lines = 7,
      new_start = 320, new_lines = 7,
      header = "@@ -320,7 +320,7 @@ function PatchView:prev_hunk_handler()\n"
    }
    local hunk_lines3 = test_hunk_4
    local hunks = { hunk1, hunk2, hunk3 }
    local hunk_segments = { hunk_lines1, hunk_lines2, hunk_lines3 }

    local merged = diff.merge_hunks(hunks, hunk_segments)

    assert.is_not_nil(merged)
    assert.array(merged).has.no.holes()
    assert.equals(#hunk_lines1 + #hunk_lines2 + #hunk_lines3, #merged)
    assert.equals("@@ -1,3 +1,5 @@", merged[1])
    assert.equals("@@ -277,9 +279,11 @@ function BitArray:set_k_unset_indices(k)", merged[#hunk_lines1+1])
    assert.equals(
      "@@ -320,7 +324,7 @@ function PatchView:prev_hunk_handler()",
      merged[#hunk_lines1+#hunk_lines2+1]
    )
  end)
end)

describe("reverse_hunk", function()
  it("reverses hunk", function()
    local hunk = {
      old_start = 1,
      old_lines = 5,
      new_start = 2,
      new_lines = 5,
      header = "@@ -1,5 +2,5 @@ test_header" .. "\n"
    }
    local hunk_lines = vim.split([[
@@ -1,5 +2,5 @@ test_header
 This is line i
 This is line i
-This is line 2
 This is line i
 This is line i
+This is line i]],
      "\n", { plain = true, trimempty = true }
    )

    local _, reversed = diff.reverse_hunk(hunk, hunk_lines)

    assert.array(reversed).has.no.holes()
    assert.equals("@@ -2,5 +2,5 @@ test_header", reversed[1])
    assert.equals(" This is line i", reversed[2])
    assert.equals("+This is line 2", reversed[4])
    assert.equals("-This is line i", reversed[7])
  end)

  it("reverses untracked hunk", function()
    local hunk = {
      old_start = 0,
      old_lines = 0,
      new_start = 1,
      new_lines = 10,
      header    = "@@ -0,0 +1,10 @@\n"
    }
    local hunk_lines = vim.split([[
@@ -0,0 +1,10 @@
+{
+    "workspace.library": [
+        "/Users/a/",
+        "/opt/a/",
+        "/Users/",
+        "${3rd}/luv/library",
+        "/nui.nvim/lua"
+    ],
+    "workspace.checkThirdParty": false
+}
    ]], "\n", { plain = true, trimempty = true })

    local _, reversed = diff.reverse_hunk(hunk, hunk_lines)

    assert.array(reversed).has.no.holes()
    assert.equals(#hunk_lines, #reversed)
    assert.equals("@@ -1,10 +0,0 @@", reversed[1])

  end)
end)
