-- Test git blame parse module

local blame = require "fugit2.core.blame"
local context = require "plenary.context_manager"

local RESOURCE_DIR = "spec/resources/"

---@param path string
---@return string
local function read_file(path)
  local result = context.with(context.open(RESOURCE_DIR .. path), function(reader)
    return reader:read "*all"
  end)
  return result
end

describe("git_blame", function()
  it("parses git blame output", function()
    local stdout = read_file "blame_a.txt"

    local hunks = blame.parse_git_blame_porcelain(stdout)

    assert.array(hunks).has.no.holes(6)
    assert.are.equal(6, #hunks)
    assert.are.equal(1, hunks[1].num_lines)
    assert.are.equal(2, hunks[4].num_lines)
    assert.are.equal(1, hunks[1].start_linenr)
    assert.are.equal(2, hunks[2].start_linenr)
    assert.are.equal(3, hunks[3].start_linenr)
    assert.are.equal(4, hunks[4].start_linenr)
    assert.are.equal(6, hunks[5].start_linenr)
    assert.are.equal("Scott Chacon", hunks[1].author_name)
    assert.are.equal("Vicent Martí", hunks[1].committer_name)
    assert.are.equal("Haneef Mubarak", hunks[2].author_name)
  end)

  it("parses git blame with uncommitted changes", function()
    local stdout = read_file "blame_b.txt"

    local hunks = blame.parse_git_blame_porcelain(stdout)

    assert.array(hunks).has.no.holes(10)
    assert.are.equal(10, #hunks)
    assert.are.equal(3, hunks[10].num_lines)
    assert.are.equal(11, hunks[10].start_linenr)
    assert.are.equal(11, hunks[10].orig_start_linenr)
    assert.are.equal("Uncommitted", hunks[10].author_name)
    assert.are.equal("Uncommitted changes", hunks[10].message)
    assert.is_nil(hunks[10].date)
  end)

  it("filters intersection between patch hunks and blame ranges", function()
    local ranges = {
      { start = 30, num = 1 },
      { start = 43, num = 2 },
      { start = 63, num = 11 },
    }
    local hunks = {
      { new_start = 25, new_lines = 4 },
      { new_start = 30, new_lines = 1 },
      { new_start = 40, new_lines = 5 },
      { new_start = 70, new_lines = 5 },
      { new_start = 76, new_lines = 10 },
    }

    local filtered = blame.filter_intersect_hunks(hunks, ranges)

    assert.array(filtered).has.no.holes()
    assert.are.equal(3, #filtered)
    assert.are.same({ 2, 3, 4 }, filtered)
  end)

  it("filters intersection between patch and many small ranges", function()
    local ranges = {
      { start = 25, num = 1 },
      { start = 26, num = 1 },
      { start = 28, num = 1 },
      { start = 70, num = 11 },
      { start = 75, num = 2 },
      { start = 79, num = 4 },
    }
    local hunks = {
      { new_start = 25, new_lines = 4 },
      { new_start = 30, new_lines = 1 },
      { new_start = 40, new_lines = 5 },
      { new_start = 70, new_lines = 10 },
    }

    local filtered = blame.filter_intersect_hunks(hunks, ranges)

    assert.array(filtered).has.no.holes()
    assert.are.equal(2, #filtered)
    assert.are.same({ 1, 4 }, filtered)
  end)
end)

describe("find_intersect_hunk", function()
  it("finds intersection between hunks and blame ranges", function()
    local hunk_raw = vim.trim [[
@@ -6,6 +6,7 @@ M.link_colors = {
   Fugit2Header = "Label",
   Fugit2ObjectId = "Comment",
   Fugit2Author = "Tag",
+  Fugit2AuthorEmail = "Label",
   Fugit2HelpHeader = "Label",
   Fugit2HelpTag = "Tag",
   Fugit2Heading = "PreProc",
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
    local hunks = {
      { old_start = 6, old_lines = 6, new_start = 6, new_lines = 7, num_lines = 7, header = hunk_lines[1] },
      { old_start = 38, old_lines = 7, new_start = 39, new_lines = 7, num_lines = 8, header = hunk_lines[9] },
    }

    local hunk1, lines1 = blame.find_intersect_hunk(hunks, hunk_lines, 8, 2)
    local hunk2, lines2 = blame.find_intersect_hunk(hunks, hunk_lines, 42, 1)
    local hunk3, lines3 = blame.find_intersect_hunk(hunks, hunk_lines, 41, 3)

    assert.is.not_nil(hunk1)
    assert.is.not_nil(hunk2)
    assert.is.not_nil(hunk3)
    assert.array(lines1).has.no.holes()
    assert.array(lines2).has.no.holes()
    assert.array(lines3).has.no.holes()
    assert.are.same(hunks[1], hunk1)
    assert.are.same(hunks[2], hunk2)
    assert.are.same(hunks[2], hunk3)
    assert.are.same(vim.list_slice(hunk_lines, 4, 5), lines1)
    assert.are.same(vim.list_slice(hunk_lines, 13, 14), lines2)
    assert.are.same(vim.list_slice(hunk_lines, 12, 15), lines3)
  end)

  it("finds intersection between hunks and blame ranges 2", function()
    local hunk = {
      header = "@@ -3,12 +3,18 @@\n",
      new_lines = 18,
      new_start = 3,
      num_lines = 18,
      old_lines = 12,
      old_start = 3,
    }

    local hunk_lines = {
      "@@ -3,12 +3,18 @@",
      " local LogLevel = vim.log.levels",
      " local uv = vim.loop",
      " ",
      '+local NuiLine = require "nui.line"',
      '+local NuiText = require "nui.text"',
      ' local Object = require "nui.object"',
      ' local Path = require "plenary.path"',
      ' local event = require("nui.utils.autocmd").event',
      " ",
      ' local git2 = require "fugit2.git2"',
      ' local SourceTree = require "fugit2.view.components.source_tree_view"',
      '+local UI = require "fugit2.view.components.menus"',
      "+",
      "+",
      "+local GIT_OID_LENGTH = 8",
      " ",
      " ---@enum Fugit2GitDiffViewPane",
    }

    local h, lines = blame.find_intersect_hunk({ hunk }, hunk_lines, 6, 2)

    assert.are.equal(2, #lines)
    assert.are.same(hunk, h)
    assert.are.same(vim.list_slice(hunk_lines, 5, 6), lines)
  end)

  it("finds intersection in many patches", function()
    local hunks = {
      {
        header = "@@ -3,12 +3,18 @@\n",
        new_lines = 18,
        new_start = 3,
        num_lines = 17,
        old_lines = 12,
        old_start = 3,
      },
      {
        header = "@@ -45,14 +51,13 @@ function GitDiff:init(ns_id, repo, index, head_commit)\n",
        new_lines = 13,
        new_start = 51,
        num_lines = 18,
        old_lines = 14,
        old_start = 45,
      },
      {
        header = "@@ -62,8 +67,21 @@ function GitDiff:init(ns_id, repo, index, head_commit)\n",
        new_lines = 21,
        new_start = 67,
        num_lines = 21,
        old_lines = 8,
        old_start = 62,
      },
    }
    local patch_raw = vim.trim [[
@@ -3,12 +3,18 @@__
 local LogLevel = vim.log.levels__
 local uv = vim.loop__
 __
+local NuiLine = require "nui.line"__
+local NuiText = require "nui.text"__
 local Object = require "nui.object"__
 local Path = require "plenary.path"__
 local event = require("nui.utils.autocmd").event__
 __
 local git2 = require "fugit2.git2"__
 local SourceTree = require "fugit2.view.components.source_tree_view"__
+local UI = require "fugit2.view.components.menus"__
+__
+local GIT_OID_LENGTH = 8__
 __
 ---@enum Fugit2GitDiffViewPane__
 local Pane = {__
@@ -45,14 +51,13 @@ function GitDiff:init(ns_id, repo, index, head_commit)__
     self.index = _index__
   end__
 __
-  if head_commit then__
-    self.head = head_commit__
-  else__
+  local _head_commit = head_commit__
+  if not head_commit then__
     local _commit, err = repo:head_commit()__
     if not _commit and err ~= git2.GIT_ERROR.GIT_EUNBORNBRANCH then__
-      error("[Fugit2] Can't get repo head " .. err)__
+      error("[Fugit2] Can't retrieve repo head " .. err)__
     end__
-    self.head = _commit__
+    _head_commit = _commit__
   end__
 __
   -- sub views__
@@ -62,8 +67,21 @@ function GitDiff:init(ns_id, repo, index, head_commit)__
   -- git info__
   self._git = {__
     path = vim.fn.fnamemodify(repo:repo_path(), ":p:h:h"),__
+    head_name = "head::",__
+    head_tree = nil,__
   }__
 __
+  if _head_commit then__
+    self._git.head_name = _head_commit:id():tostring(GIT_OID_LENGTH) .. "::"__
+__
+    local _tree, err = _head_commit:tree()__
+    if _tree then__
+      self._git.head_tree = _tree__
+    else__
+      error("[Fugit2] Cant' retrieve head tree" .. err)__
+    end__
+  end__
+__
   -- states__
   self._states = {__
     pane = Pane.SINGLE,__
    ]]
    local patch = vim.split(patch_raw, "__\n", { plain = true, trimempty = false })

    local hunk, lines = blame.find_intersect_hunk(hunks, patch, 74, 11)

    assert.is.not_nil(hunk)
    assert.is.not_nil(lines)
    assert.are.same(hunks[3], hunk)
    assert.are.equal(11, #lines)
    assert.are.same(vim.list_slice(patch, 46, 56), lines)
  end)
end)
