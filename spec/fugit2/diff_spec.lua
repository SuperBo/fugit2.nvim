-- Test  diff util module

local context = require "plenary.context_manager"
local diff = require "fugit2.diff"
local git2 = require "fugit2.git2"

---@param path string
---@return string
local function read_patch_file(path)
  local ret = ""
  context.with(context.open(path, "r"), function(reader)
    ret = reader:read "*all"
  end)
  return ret
end

describe("parse_patch", function()
  local patch = read_patch_file "spec/resources/patch_a.diff"

  it("get correct header", function()
    local patch_item = diff.parse_patch(patch)

    assert.is.not_nil(patch_item.header)
    assert.array(patch_item.header).has.no.holes(4)
    assert.are.equal(4, #patch_item.header)
  end)

  it("get correct num hunk", function()
    local patch_item = diff.parse_patch(patch)

    assert.is.not_nil(patch_item.hunks)
    assert.array(patch_item.hunks).has.no.holes(4)
    assert.are.equal(4, #patch_item.hunks)
  end)

  it("get correct hunk", function()
    local patch_item = diff.parse_patch(patch)

    assert.is.not_nil(patch_item.hunks)
    assert.is.not_nil(patch_item.hunks[4])

    local hunk = patch_item.hunks[4]

    assert.are.equal("@@ -149,4 +172,23 @@ function PatchView:unmount()", hunk.header)
    assert.are.equal(" return PatchView", hunk.lines[#hunk.lines].text)
    assert.are.equal(" ", hunk.lines[#hunk.lines].c)
    assert.are.equal(92, hunk.lines[#hunk.lines].linenr)
    assert.are.equal(23, #hunk.lines)
  end)
end)

describe("patch_sub_lines", function()
  local patch_lines --[[@as string[] ]]
  local hunks --[[@as GitDiffHunk[] ]]

  setup(function()
    local patch = read_patch_file "spec/resources/patch_a.diff"
    local lines = vim.split(patch, "\n", { plain = true, trimempty = true })
    patch_lines = vim.list_slice(lines, 5)
    hunks = {
      { old_start = 50, old_lines = 6, new_start = 50, new_lines = 11, num_lines = 11 },
      { old_start = 59, old_lines = 11, new_start = 64, new_lines = 20, num_lines = 25 },
      { old_start = 99, old_lines = 11, new_start = 113, new_lines = 20, num_lines = 25 },
      { old_start = 149, old_lines = 4, new_start = 172, new_lines = 23, num_lines = 23 },
    }
  end)

  it("selects all when empty indices", function()
    local selected_lines, selected_hunks = diff.patch_sub_lines(patch_lines, hunks, {})

    assert.array(selected_lines).has.no.holes()
    assert.array(selected_hunks).has.no.holes()
    assert.are.equal(#patch_lines, #selected_lines)
    assert.are.equal(#hunks, #selected_hunks)
    assert.are.same(patch_lines, selected_lines)
    assert.are.same(hunks, selected_hunks)
  end)

  it("selects all indices", function()
    local selected_lines, selected_hunks = diff.patch_sub_lines(patch_lines, hunks, { 1, 2, 3, 4 })

    assert.array(selected_lines).has.no.holes()
    assert.array(selected_hunks).has.no.holes()
    assert.are.equal(#patch_lines, #selected_lines)
    assert.are.equal(#hunks, #selected_hunks)
    assert.are.same(patch_lines, selected_lines)
    assert.are.same(hunks, selected_hunks)
  end)

  it("selects first hunk", function()
    local selected_lines, selected_hunks = diff.patch_sub_lines(patch_lines, hunks, { 1 })

    assert.array(selected_lines).has.no.holes()
    assert.array(selected_hunks).has.no.holes()
    assert.are.equal(hunks[1].num_lines + 1, #selected_lines)
    assert.are.equal(1, #selected_hunks)
    assert.are.same(hunks[1], selected_hunks[1])
    assert.are.same(vim.list_slice(patch_lines, 1, hunks[1].num_lines + 1), selected_lines)
  end)

  it("selects last hunk", function()
    local selected_lines, selected_hunks = diff.patch_sub_lines(patch_lines, hunks, { 4 })

    assert.array(selected_lines).has.no.holes()
    assert.array(selected_hunks).has.no.holes()
    assert.are.equal(hunks[4].num_lines + 1, #selected_lines)
    assert.are.equal(1, #selected_hunks)
    assert.are.same(hunks[4], selected_hunks[1])
    assert.are.same(vim.list_slice(patch_lines, 65, 65 + hunks[4].num_lines), selected_lines)
  end)

  it("selects two consecutive hunks", function()
    local selected_lines, selected_hunks = diff.patch_sub_lines(patch_lines, hunks, { 1, 2 })

    assert.array(selected_lines).has.no.holes()
    assert.array(selected_hunks).has.no.holes()
    assert.are.equal(2, #selected_hunks)
    assert.are.same({ hunks[1], hunks[2] }, selected_hunks)
    assert.are.equal(hunks[1].num_lines + hunks[2].num_lines + 2, #selected_lines)
    assert.are.same(vim.list_slice(patch_lines, 1, hunks[1].num_lines + hunks[2].num_lines + 2), selected_lines)
  end)

  it("selects two gap hunks", function()
    local selected_lines, selected_hunks = diff.patch_sub_lines(patch_lines, hunks, { 2, 4 })

    assert.array(selected_lines).has.no.holes()
    assert.array(selected_hunks).has.no.holes()
    assert.are.equal(2, #selected_hunks)
    assert.are.same({ hunks[2], hunks[4] }, selected_hunks)
    assert.are.equal(hunks[2].num_lines + hunks[4].num_lines + 2, #selected_lines)
    assert.are.same(
      vim.list_extend(
        vim.list_slice(patch_lines, hunks[1].num_lines + 2, hunks[1].num_lines + hunks[2].num_lines + 2),
        vim.list_slice(patch_lines, 65, 65 + hunks[4].num_lines)
      ),
      selected_lines
    )
  end)
end)

describe("select_hunk_lines", function()
  it("selects none when out of range", function()
    local hunk_raw = vim.trim [[
@@ -38,7 +39,7 @@ M.link_colors = {
   Fugit2RebasePick = "diffAdded", -- green
   Fugit2RebaseDrop = "diffRemoved", -- red
   Fugit2RebaseSquash = "Type", -- yellow
-  Fugit2BlameDate = "Comment",
+  Fugit2BlameDate = "Constant",
   Fugit2BlameBorder = "Comment",
   Fugit2Branch1 = "diffAdded", -- green
   Fugit2Branch2 = "DiagnosticInfo", --dark blue
    ]]
    local hunk_lines = vim.split(hunk_raw, "\n", { plain = true, trimempty = true })
    local hunk = { old_start = 38, old_lines = 7, new_start = 39, new_lines = 7, header = hunk_lines[1] }

    local select1 = diff.select_hunk_lines(hunk, hunk_lines, 20, 8)
    local select2 = diff.select_hunk_lines(hunk, hunk_lines, 28, 6)
    local select3 = diff.select_hunk_lines(hunk, hunk_lines, 38, 1)
    local select4 = diff.select_hunk_lines(hunk, hunk_lines, 46, 1)
    local select5 = diff.select_hunk_lines(hunk, hunk_lines, 47, 10)

    assert.is_nil(select1)
    assert.is_nil(select2)
    assert.is_nil(select3)
    assert.is_nil(select4)
    assert.is_nil(select5)
  end)

  it("selects added and removed lines", function()
    local hunk_raw = vim.trim [[
@@ -38,7 +39,7 @@ M.link_colors = {
   Fugit2RebasePick = "diffAdded", -- green
   Fugit2RebaseDrop = "diffRemoved", -- red
   Fugit2RebaseSquash = "Type", -- yellow
-  Fugit2BlameDate = "Comment",
+  Fugit2BlameDate = "Constant",
   Fugit2BlameBorder = "Comment",
   Fugit2Branch1 = "diffAdded", -- green
   Fugit2Branch2 = "DiagnosticInfo", --dark blue
    ]]
    local hunk_lines = vim.split(hunk_raw, "\n", { plain = true, trimempty = true })
    local hunk = { old_start = 38, old_lines = 7, new_start = 39, new_lines = 7, header = hunk_lines[1] }

    local select1 = diff.select_hunk_lines(hunk, hunk_lines, 42, 1)
    local select2 = diff.select_hunk_lines(hunk, hunk_lines, 41, 2)
    local select3 = diff.select_hunk_lines(hunk, hunk_lines, 42, 2)

    assert.array(select1).has.no.holes()
    assert.array(select2).has.no.holes()
    assert.array(select3).has.no.holes()
    assert.are.same(vim.list_slice(hunk_lines, 5, 6), select1)
    assert.are.same(vim.list_slice(hunk_lines, 4, 6), select2)
    assert.are.same(vim.list_slice(hunk_lines, 5, 7), select3)
  end)

  it("selects context lines", function()
    local hunk_raw = vim.trim [[
@@ -10,4 +10,7 @@
 ---Diff helper module
+
+local table_new = require "table.new"
+
 ---@module 'Fugit2DiffHelper'
 local M = {}
 
    ]]
    local hunk_lines = vim.split(hunk_raw, "\n", { plain = true, trimempty = true })
    local hunk = { old_start = 10, old_lines = 4, new_start = 10, new_lines = 7, header = hunk_lines[1] }

    local select1 = diff.select_hunk_lines(hunk, hunk_lines, 10, 1)
    local select2 = diff.select_hunk_lines(hunk, hunk_lines, 8, 4)
    local select3 = diff.select_hunk_lines(hunk, hunk_lines, 14, 8)

    assert.array(select1).has.no.holes()
    assert.array(select2).has.no.holes()
    assert.array(select3).has.no.holes()
    assert.are.same(vim.list_slice(hunk_lines, 2, 2), select1)
    assert.are.same(vim.list_slice(hunk_lines, 2, 3), select2)
    assert.are.same(vim.list_slice(hunk_lines, 6, 8), select3)
  end)

  it("selects sub lines", function()
    local hunk_raw = vim.trim [[
@@ -10,8 +10,8 @@
 ---Diff helper module
-hello1
-hello2
-hello3
-hello4
+
+local table_new = require "table.new"
+local git2 = require "fugit2.git2"
+
 ---@module 'Fugit2DiffHelper'
 local M = {}
 
    ]]
    local hunk_lines = vim.split(hunk_raw, "\n", { plain = true, trimempty = true })
    local hunk = { old_start = 10, old_lines = 8, new_start = 10, new_lines = 8, header = hunk_lines[1] }

    local select1 = diff.select_hunk_lines(hunk, hunk_lines, 11, 1)
    local select2 = diff.select_hunk_lines(hunk, hunk_lines, 12, 1)
    local select3 = diff.select_hunk_lines(hunk, hunk_lines, 12, 2)
    local select4 = diff.select_hunk_lines(hunk, hunk_lines, 11, 4)

    assert.array(select1).has.no.holes()
    assert.array(select2).has.no.holes()
    assert.array(select3).has.no.holes()
    assert.array(select4).has.no.holes()
    assert.are.same({ hunk_lines[3], hunk_lines[7] }, select1)
    assert.are.same({ hunk_lines[4], hunk_lines[8] }, select2)
    assert.are.same({ hunk_lines[4], hunk_lines[5], hunk_lines[8], hunk_lines[9] }, select3)
    assert.are.same(vim.list_slice(hunk_lines, 3, 10), select4)
  end)
end)

describe("numbering_hunk_lines", function()
  it("numbering added only hunk", function()
    local hunk_raw = vim.trim [[
@@ -6,6 +6,7 @@ M.link_colors = {
   Fugit2Header = "Label",
   Fugit2ObjectId = "Comment",
   Fugit2Author = "Tag",
+  Fugit2AuthorEmail = "Label",
   Fugit2HelpHeader = "Label",
   Fugit2HelpTag = "Tag",
   Fugit2Heading = "PreProc",
    ]]
    local hunk_lines = vim.split(hunk_raw, "\n", { plain = true, trimempty = true })
    local hunk =
      { num_lines = #hunk_lines, old_start = 6, old_lines = 6, new_start = 6, new_lines = 7, header = hunk_lines[1] }
    local numbers = diff.numbering_hunk_lines(hunk, hunk_lines)

    assert.array(numbers).has.no.holes()
    assert.are.equal(#hunk_lines, #numbers)
    assert.are.same({ 0, 6, 7, 8, 9, 10, 11, 12 }, numbers)
  end)

  it("numbering minus only hunk", function()
    local hunk_raw = vim.trim [[
@@ -73,7 +73,6 @@ end
 ---@param n number
 ---@return number
 function M.round(n)
-  return math.floor((math.floor(n * 2) + 1) / 2)
 end
 
 ---@param str string
    ]]
    local hunk_lines = vim.split(hunk_raw, "\n", { plain = true, trimempty = true })
    local hunk =
      { num_lines = #hunk_lines, old_start = 73, old_lines = 7, new_start = 73, new_lines = 6, header = hunk_lines[1] }

    local numbers = diff.numbering_hunk_lines(hunk, hunk_lines)

    assert.array(numbers).has.no.holes()
    assert.are.equal(#hunk_lines, #numbers)
    assert.are.same({ 0, 73, 74, 75, 76, 76, 77, 78 }, numbers)
  end)

  it("numbering complex hunk", function()
    local hunk_raw = vim.trim [[
@@ -102,17 +102,7 @@ function PatchView:update(patch_item)
     )
   end
 
-  local lines = vim.split(tostring(patch), "\n", { plain = true, trimempty = true })
-
-  for i, l in ipairs(lines) do
-    if l:sub(1, 1) ~= "@" then
-      header[i] = l
-    else
-      break
-    end
-  end
-
-  local render_lines = vim.list_slice(lines, #header + 1)
+  local header, hunk_lines = diff_utils.split_patch(tostring(patch))
 
   local line_num = hunk_offsets[1]
   for i = 0, patch_item.num_hunks - 1 do
    ]]
    local hunk_lines = vim.split(hunk_raw, "\n", { plain = true, trimempty = true })
    local hunk = {
      num_lines = #hunk_lines,
      old_start = 102,
      old_lines = 17,
      new_start = 102,
      new_lines = 7,
      header = hunk_lines[1],
    }

    local numbers = diff.numbering_hunk_lines(hunk, hunk_lines)

    assert.array(numbers).has.no.holes()
    assert.are.equal(#hunk_lines, #numbers)
    assert.are.same(
      { 0, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 105, 106, 107, 108 },
      numbers
    )
  end)
end)

describe("partial_patch_from_hunk", function()
  local patch = read_patch_file "spec/resources/patch_a.diff"
  local function read_hunk(idx)
    local patch_item = diff.parse_patch(patch)

    local header = patch_item.header
    local hunk_header = ""
    local hunk_lines = {}

    local hunk = patch_item.hunks[idx]
    if hunk then
      hunk_header = hunk.header
      hunk_lines = vim.tbl_map(function(value)
        return value.text
      end, hunk.lines)
    end

    return header, hunk_header, hunk_lines
  end

  setup(function()
    local path = require("os").getenv "GIT2_DIR"
    require("fugit2.libgit2").setup_lib(path and path .. "/lib/libgit2.so" or nil)
  end)

  it("creates partial patch", function()
    local header, hunk_header, hunk_lines = read_hunk(1)

    local partial_patch = diff.partial_patch_from_hunk(header, hunk_header, hunk_lines)

    assert.is.not_nil(partial_patch)
    assert.are.equal("string", type(partial_patch))
    assert.are.equal(
      [[diff --git a/lua/fugit2/view/components/patch_view.lua b/lua/fugit2/view/components/patch_view.lua
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
      partial_patch
    )
  end)

  it("creates partial patch 2", function()
    local header, hunk_header, hunk_lines = read_hunk(4)

    local partial_patch = diff.partial_patch_from_hunk(header, hunk_header, hunk_lines)

    assert.is.not_nil(partial_patch)
    assert.are.equal("string", type(partial_patch))
    assert.are.equal(
      [[diff --git a/lua/fugit2/view/components/patch_view.lua b/lua/fugit2/view/components/patch_view.lua
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
      partial_patch
    )
  end)

  it("create valid git2 diff", function()
    local header, hunk_header, hunk_lines = read_hunk(4)

    local partial_patch = diff.partial_patch_from_hunk(header, hunk_header, hunk_lines)

    assert.is.not_nil(partial_patch)

    local diff, err = git2.Diff.from_buffer(partial_patch)

    assert.are.equal(0, err)
    assert.is.not_nil(diff)
    assert.is.not_nil(diff.diff)
  end)
end)

describe("partial_hunk", function()
  local test_hunk_1 = vim.split(
    [[
@@ -219,7 +232,7 @@ function PatchView:prev_hunk_handler()
       if hunk_idx <= 1 then
         new_row = 1
       else
-        new_row = self._hunks[hunk_idx-1]
+        new_row = self._hunk_offsets[hunk_idx-1]
       end
     end
     vim.api.nvim_win_set_cursor(self.popup.winid, { new_row, col })]],
    "\n",
    { plain = true, trimempty = true }
  )

  local test_hunk_2 = vim.split(
    [[
@@ -1,3 +1,5 @@
+local utils = require "fugit2.utils"
+
 ---Diff helper module
 ---@module 'Fugit2DiffHelper'
 local M = {}
    ]],
    "\n",
    { plain = true, trimempty = true }
  )

  local test_hunk_3 = vim.split(
    [[
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
    "\n",
    { plain = true, trimempty = true }
  )

  local test_hunk_4 = vim.split(
    [[
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
    "\n",
    { plain = true, trimempty = true }
  )

  it("extracts partial_hunk", function()
    local hunk = {
      old_start = 219,
      old_lines = 7,
      new_start = 232,
      new_lines = 7,
      header = "@@ -219,7 +232,7 @@ function PatchView:prev_hunk_handler()\n",
    }
    local hunk_lines = test_hunk_1

    local _, partial = diff.partial_hunk(hunk, hunk_lines)

    assert.array(partial).has.no.holes(#hunk_lines)
    assert.are.equal(#hunk_lines, #partial)
    assert.are.equal("@@ -219,7 +219,7 @@ function PatchView:prev_hunk_handler()", partial[1])
    assert.are.equal("       if hunk_idx <= 1 then", partial[2])
  end)

  it("extracts untracked hunk", function()
    local hunk = {
      old_start = 0,
      old_lines = 0,
      new_start = 1,
      new_lines = 10,
      header = "@@ -0,0 +1,10 @@\n",
    }
    local hunk_lines = vim.split(
      [[
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
    ]],
      "\n",
      { plain = true, trimempty = true }
    )

    local _, partial = diff.partial_hunk(hunk, hunk_lines)

    assert.array(partial).has.no.holes(#hunk_lines)
    assert.are.equal(#hunk_lines, #partial)
    assert.are.equal("@@ -0,0 +1,10 @@", partial[1])
  end)

  it("extracts selected partial hunk 1", function()
    local hunk = {
      old_start = 1,
      old_lines = 3,
      new_start = 1,
      new_lines = 5,
      header = "@@ -1,3 +1,5 @@\n",
    }
    local hunk_lines = test_hunk_2

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 1, 2, false)

    assert.array(selected).has.no.holes()
    assert.are.equal("@@ -1,3 +1,4 @@", selected[1])
    assert.are.equal(" ---Diff helper module", selected[3])
  end)

  it("extracts selected partial hunk 2", function()
    local hunk = {
      old_start = 1,
      old_lines = 3,
      new_start = 1,
      new_lines = 5,
      header = "@@ -1,3 +1,5 @@\n",
    }
    local hunk_lines = test_hunk_2

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 1, 3, false)

    assert.array(selected).has.no.holes()
    assert.are.equal("@@ -1,3 +1,5 @@", selected[1])
    assert.are.equal("+", selected[3])
  end)

  it("extracts selected partial hunk 3", function()
    local hunk = {
      old_start = 277,
      old_lines = 9,
      new_start = 277,
      new_lines = 11,
      header = "@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)\n",
    }
    local hunk_lines = test_hunk_3

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 1, 6, false)

    assert.array(selected).has.no.holes(9)
    assert.are.equal(9, #selected)
    assert.are.equal("@@ -277,8 +277,6 @@ function BitArray:set_k_unset_indices(k)", selected[1])
    assert.are.equal("   local i = 1", selected[9])
  end)

  it("extracts selected partial hunk 4", function()
    local hunk = {
      old_start = 277,
      old_lines = 9,
      new_start = 277,
      new_lines = 11,
      header = "@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)\n",
    }
    local hunk_lines = test_hunk_3

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 7, 10, false)

    assert.is.not_nil(selected)
    assert.array(selected).has.no.holes(13)
    assert.are.equal(13, #selected)
    assert.are.equal("@@ -277,9 +277,12 @@ function BitArray:set_k_unset_indices(k)", selected[1])
    assert.are.equal(" ---@param lst table", selected[6])
    assert.are.equal("+---@generic T", selected[8])
    assert.are.equal(" function M.list_sorted_insert(lst, ele)", selected[11])
  end)

  it("extracts selected partial hunk with minus line non-selected", function()
    local hunk = {
      old_start = 219,
      old_lines = 7,
      newproxy = 232,
      new_lines = 7,
      header = "@@ -219,7 +232,7 @@ function PatchView:prev_hunk_handler()\n",
    }
    local hunk_lines = test_hunk_1

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 6, 7, false)

    assert.is.not_nil(selected)
    assert.array(selected).has.no.holes()
    assert.are.equal(#hunk_lines, #selected)
    assert.are.equal("@@ -219,7 +219,8 @@ function PatchView:prev_hunk_handler()", selected[1])
    assert.are.equal("         new_row = self._hunks[hunk_idx-1]", selected[5])
    assert.are.equal("+        new_row = self._hunk_offsets[hunk_idx-1]", selected[6])
  end)

  it("extracts selected partial hunk for reverse 1", function()
    local hunk = {
      old_start = 219,
      old_lines = 7,
      new_start = 232,
      new_lines = 7,
      header = "@@ -219,7 +232,7 @@ function PatchView:prev_hunk_handler()\n",
    }
    local hunk_lines = test_hunk_1

    local _, partial = diff.partial_hunk_selected(hunk, hunk_lines, 3, 5, true)

    assert.array(partial).has.no.holes(8)
    assert.are.equal(8, #partial)
    assert.are.equal("@@ -219,7 +219,6 @@ function PatchView:prev_hunk_handler()", partial[1])
    assert.are.equal("-        new_row = self._hunks[hunk_idx-1]", partial[5])
    assert.are.equal("         new_row = self._hunk_offsets[hunk_idx-1]", partial[6])
  end)

  it("returns nil for context only selection", function()
    local hunk = {
      old_start = 277,
      old_lines = 9,
      new_start = 277,
      new_lines = 11,
      header = "@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)\n",
    }
    local hunk_lines = test_hunk_3

    local _, selected = diff.partial_hunk_selected(hunk, hunk_lines, 1, 3, false)

    assert.is_nil(selected)
  end)

  it("merges 2 partial hunks into one", function()
    local hunk1 = {
      old_start = 1,
      old_lines = 3,
      new_start = 1,
      new_lines = 5,
      header = "@@ -1,3 +1,5 @@\n",
    }
    local hunk_lines1 = test_hunk_2
    local hunk2 = {
      old_start = 277,
      old_lines = 9,
      new_start = 277,
      new_lines = 11,
      header = "@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)\n",
    }
    local hunk_lines2 = test_hunk_3
    local hunks = { hunk1, hunk2 }
    local hunk_segments = { hunk_lines1, hunk_lines2 }

    local merged = diff.merge_hunks(hunks, hunk_segments)

    assert.is.not_nil(merged)
    assert.array(merged).has.no.holes()
    assert.are.equal(#hunk_lines1 + #hunk_lines2, #merged)
    assert.are.equal("@@ -1,3 +1,5 @@", merged[1])
    assert.are.equal("@@ -277,9 +279,11 @@ function BitArray:set_k_unset_indices(k)", merged[#hunk_lines1 + 1])
  end)

  it("merges 3 partial hunks into one", function()
    local hunk1 = {
      old_start = 1,
      old_lines = 3,
      new_start = 1,
      new_lines = 5,
      header = "@@ -1,3 +1,5 @@\n",
    }
    local hunk_lines1 = test_hunk_2
    local hunk2 = {
      old_start = 277,
      old_lines = 9,
      new_start = 277,
      new_lines = 11,
      header = "@@ -277,9 +277,11 @@ function BitArray:set_k_unset_indices(k)\n",
    }
    local hunk_lines2 = test_hunk_3
    local hunk3 = {
      old_start = 320,
      old_lines = 7,
      new_start = 320,
      new_lines = 7,
      header = "@@ -320,7 +320,7 @@ function PatchView:prev_hunk_handler()\n",
    }
    local hunk_lines3 = test_hunk_4
    local hunks = { hunk1, hunk2, hunk3 }
    local hunk_segments = { hunk_lines1, hunk_lines2, hunk_lines3 }

    local merged = diff.merge_hunks(hunks, hunk_segments)

    assert.is.not_nil(merged)
    assert.array(merged).has.no.holes()
    assert.are.equal(#hunk_lines1 + #hunk_lines2 + #hunk_lines3, #merged)
    assert.are.equal("@@ -1,3 +1,5 @@", merged[1])
    assert.are.equal("@@ -277,9 +279,11 @@ function BitArray:set_k_unset_indices(k)", merged[#hunk_lines1 + 1])
    assert.are.equal(
      "@@ -320,7 +324,7 @@ function PatchView:prev_hunk_handler()",
      merged[#hunk_lines1 + #hunk_lines2 + 1]
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
      header = "@@ -1,5 +2,5 @@ test_header\n",
    }
    local hunk_lines = vim.split(
      [[
@@ -1,5 +2,5 @@ test_header
 This is line i
 This is line i
-This is line 2
 This is line i
 This is line i
+This is line i]],
      "\n",
      { plain = true, trimempty = true }
    )

    local _, reversed = diff.reverse_hunk(hunk, hunk_lines)

    assert.array(reversed).has.no.holes()
    assert.are.equal("@@ -2,5 +2,5 @@ test_header", reversed[1])
    assert.are.equal(" This is line i", reversed[2])
    assert.are.equal("+This is line 2", reversed[4])
    assert.are.equal("-This is line i", reversed[7])
  end)

  it("reverses untracked hunk", function()
    local hunk = {
      old_start = 0,
      old_lines = 0,
      new_start = 1,
      new_lines = 10,
      header = "@@ -0,0 +1,10 @@\n",
    }
    local hunk_lines = vim.split(
      [[
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
    ]],
      "\n",
      { plain = true, trimempty = true }
    )

    local _, reversed = diff.reverse_hunk(hunk, hunk_lines)

    assert.array(reversed).has.no.holes(#hunk_lines)
    assert.are.equal(#hunk_lines, #reversed)
    assert.are.equal("@@ -1,10 +0,0 @@", reversed[1])
  end)

  it("gets line number at context line", function()
    local hunk = {
      old_start = 764,
      old_lines = 6,
      new_start = 788,
      new_lines = 16,
      header = "@@ -764,6 +788,16 @@ function GitStatus:_init_patch_views()\n",
    }
    local hunk_lines = vim.split(
      [[
@@ -764,6 +788,16 @@ function GitStatus:_init_patch_views()
   patch_unstaged:map("v", { "d", "x" }, function()
     self._prompts.discard_line_confirm:show()
   end, opts)
+
+  -- Enter to jump to file
+  patch_unstaged:map("n", "<cr>", function()
+    local node, _ = tree:get_child_node_linenr()
+    local linenr = patch_unstaged:file_line()
+    if node then
+      self:unmount()
+      open_file(self._git.path, node.id, linenr)
+    end
+  end, opts)
 end
 
 -- Read git config
      ]],
      "\n",
      { plain = true, trimempty = true }
    )

    local line0 = diff.file_line(hunk, hunk_lines, 0)
    local line1 = diff.file_line(hunk, hunk_lines, 1)
    local line2 = diff.file_line(hunk, hunk_lines, 2)
    local line14 = diff.file_line(hunk, hunk_lines, 14)
    local line15 = diff.file_line(hunk, hunk_lines, 15)
    local line16 = diff.file_line(hunk, hunk_lines, 16)

    assert.are.equal(788, line0)
    assert.are.equal(788, line1)
    assert.are.equal(789, line2)
    assert.are.equal(801, line14)
    assert.are.equal(802, line15)
    assert.are.equal(803, line16)
  end)

  it("gets line number at added line", function()
    local hunk = {
      old_start = 764,
      old_lines = 6,
      new_start = 788,
      new_lines = 16,
      header = "@@ -764,6 +788,16 @@ function GitStatus:_init_patch_views()\n",
    }
    local hunk_lines = vim.split(
      [[
@@ -764,6 +788,16 @@ function GitStatus:_init_patch_views()
   patch_unstaged:map("v", { "d", "x" }, function()
     self._prompts.discard_line_confirm:show()
   end, opts)
+
+  -- Enter to jump to file
+  patch_unstaged:map("n", "<cr>", function()
+    local node, _ = tree:get_child_node_linenr()
+    local linenr = patch_unstaged:file_line()
+    if node then
+      self:unmount()
+      open_file(self._git.path, node.id, linenr)
+    end
+  end, opts)
 end
 
 -- Read git config
      ]],
      "\n",
      { plain = true, trimempty = true }
    )

    local line4 = diff.file_line(hunk, hunk_lines, 4)
    local line6 = diff.file_line(hunk, hunk_lines, 6)
    local line10 = diff.file_line(hunk, hunk_lines, 10)

    assert.are.equal(791, line4)
    assert.are.equal(793, line6)
    assert.are.equal(797, line10)
  end)

  it("gets line number at removed line", function()
    local hunk = {
      old_start = 2194,
      old_lines = 14,
      new_start = 2228,
      new_lines = 7,
      header = "@@ -764,6 +788,16 @@ function GitStatus:_init_patch_views()\n",
    }
    local hunk_lines = vim.split(
      [[
@@ -2194,14 +2228,7 @@ function GitStatus:setup_handlers()
     --   end
     elseif node then
       exit_fn()
-      local cwd = vim.fn.getcwd()
-      local current_file = vim.api.nvim_buf_get_name(0)
-
-      local file_path = Path:new(self._git.path) / vim.fn.fnameescape(node.id)
-
-      if tostring(file_path) ~= current_file then
-        vim.cmd.edit(file_path:make_relative(cwd))
-      end
+      open_file(self._git.path, node.id)
     end
   end, map_options)
 
      ]],
      "\n",
      { plain = true, trimempty = true }
    )

    local line4 = diff.file_line(hunk, hunk_lines, 4)
    local line6 = diff.file_line(hunk, hunk_lines, 6)
    local line10 = diff.file_line(hunk, hunk_lines, 10)
    local line12 = diff.file_line(hunk, hunk_lines, 12)

    assert.are.equal(2231, line4)
    assert.are.equal(2231, line6)
    assert.are.equal(2231, line10)
    assert.are.equal(2231, line12)
  end)
end)
