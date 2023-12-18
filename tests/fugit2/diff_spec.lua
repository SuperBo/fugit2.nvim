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
  it("extracts partial_hunk", function()
    local hunk = {
      old_start = 219,
      old_lines = 7,
      new_start = 232,
      new_lines = 7,
      header = "@@ -219,7 +232,7 @@ function PatchView:prev_hunk_handler()\n"
    }
    local hunk_lines = vim.split([[
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

    local partial = diff.partial_hunk(hunk, hunk_lines)

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

    local partial = diff.partial_hunk(hunk, hunk_lines)

    assert.array(partial).has.no.holes()
    assert.equals(#hunk_lines, #partial)
    assert.equals("@@ -0,0 +1,10 @@", partial[1])
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

    local reversed = diff.reverse_hunk(hunk, hunk_lines)

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

    local reversed = diff.reverse_hunk(hunk, hunk_lines)

    assert.array(reversed).has.no.holes()
    assert.equals(#hunk_lines, #reversed)
    assert.equals("@@ -1,10 +0,0 @@", reversed[1])

  end)
end)
