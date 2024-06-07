-- GitBlame inside view using virtual texts

local Object = require "nui.object"
local Path = require "plenary.path"
local PlenaryJob = require "plenary.job"
local keymap = require "nui.utils.keymap"
local strings = require "plenary.strings"

local blame = require "fugit2.core.blame"
local config = require "fugit2.config"
local notifier = require "fugit2.notifier"
local utils = require "fugit2.utils"

---@class Fugit2GitBlameFile
---@field ns_id integer namespace number
---@field repo GitRepository git repository
local GitBlameFile = Object "Fugit2GitBlameFile"

-- Inits GitBlameFile object
-- Used when callling Fuguit2Blame file
---@param ns_id integer namespace number
---@param repo GitRepository git repository
---@param file_bufnr integer file buffer
function GitBlameFile:init(ns_id, repo, file_bufnr)
  self.ns_id = ns_id
  self.file_bufnr = file_bufnr

  local file_path = Path:new(vim.fn.fnameescape(vim.api.nvim_buf_get_name(file_bufnr)))
  local git_path = vim.fn.fnamemodify(repo:repo_path(), ":p:h:h")

  self._git = {
    repo = repo,
    file_path = file_path:make_relative(git_path),
    path = git_path,
    hunk_offsets = {} --[[@as integer[] ]],
    authors_map = {} --[[@as {[string]: integer} ]],
  }

  self._states = {}
end

-- Updates blame hunks.
---@return Fugit2GitBlameHunk[]? git blame hunks
function GitBlameFile:update()
  local git = self._git
  local repo = git.repo

  local head, err = repo:head_tree()
  if not head then
    notifier.error("Failed to retrieve HEAD", err)
    return nil
  end
  local entry
  entry, err = head:entry_bypath(git.file_path)
  if not entry then
    notifier.error("Failed to find " .. git.file_path, err)
    return nil
  end

  local job = PlenaryJob:new {
    command = "git",
    args = { "blame", "--date=unix", "--porcelain", git.file_path },
    cwd = git.path,
    enable_recording = true,
  }

  local result
  result, err = job:sync(5000, 200) -- wait till 5 seconds
  if err ~= 0 then
    result = job:stderr_result()
    local stderr = #result > 0 and result[1] or ""
    notifier.error("Git blame error, " .. stderr, err)
    return nil
  end

  local hunks = blame.parse_git_blame_porcelain_lines(result)

  local authors_map = {}
  local total_lines = 0
  local offsets = utils.list_new(#hunks)

  for i, h in ipairs(hunks) do
    authors_map[h.author_name] = 1
    offsets[i] = total_lines + 1
    total_lines = total_lines + h.num_lines
  end

  git.hunk_offsets = offsets
  git.num_lines = total_lines

  -- build author index table
  local authors = {}
  for a, _ in pairs(authors_map) do
    authors[#authors + 1] = a
  end
  table.sort(authors)
  for i, a in ipairs(authors) do
    authors_map[a] = i - 1
  end

  git.authors_map = authors_map

  return hunks
end

-- Renders hunks as virtual text in to file buffer.
---@param hunks Fugit2GitBlameHunk[]
function GitBlameFile:render(hunks)
  local bufnr = self.file_bufnr
  local ns_id = self.ns_id
  local nlines = vim.api.nvim_buf_line_count(bufnr)

  local authors_map = self._git.authors_map
  local author_len = 1
  for author, _ in pairs(authors_map) do
    author_len = math.max(author:len() + 1, author_len)
  end

  local time_len = string.len "60 minutes ago"
  local virt_text_priority = config.get_number "blame_priority" or 1
  local today = os.date "*t" --[[@as osdateparam]]

  vim.api.nvim_buf_set_var(bufnr, "fugit2_blame_is_loaded", true)

  for _, hunk in ipairs(hunks) do
    if hunk.start_linenr > nlines then
      break
    end

    local time_ago = "---"
    local age_color = 10

    if hunk.date then
      time_ago, age_color = blame.blame_time(hunk.date, today)
    end

    local hl_group = "Fugit2BlameAge" .. age_color
    local virt_text = {
      { strings.align_str(time_ago, time_len), hl_group },
      { " " .. strings.align_str(hunk.author_name, author_len), hl_group },
      { hunk.num_lines > 1 and "┐" or " ", hl_group },
    }

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, hunk.start_linenr - 1, 0, {
      virt_text = virt_text,
      virt_text_pos = "inline",
      virt_text_repeat_linebreak = true,
      priority = virt_text_priority,
      -- sign_text=hunk.num_lines > 1 and "┌" or "-",
      -- sign_hl_group=hl_group,
      -- number_hl_group=hl_group,
    })

    if hunk.num_lines > 1 then
      virt_text[3][1] = "│"
      for i = 1, hunk.num_lines - 2 do
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, hunk.start_linenr + i - 1, 0, {
          virt_text_pos = "inline",
          virt_text = virt_text,
          virt_text_repeat_linebreak = true,
          priority = virt_text_priority,
          -- sign_text="╎",
          -- sign_hl_group=hl_group,
          -- number_hl_group=hl_group,
        })
      end

      virt_text[3][1] = "┘"
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, hunk.start_linenr + hunk.num_lines - 2, 0, {
        virt_text_pos = "inline",
        virt_text = virt_text,
        virt_text_repeat_linebreak = true,
        priority = virt_text_priority,
        -- sign_text="└",
        -- sign_hl_group=hl_group,
        -- number_hl_group=hl_group,
      })
    end
  end
end

-- setup handlers in main buffer
function GitBlameFile:setup_handlers()
  local opts = { noremap = true, nowait = true }
  local bufnr = self.file_bufnr

  -- quit event
  keymap.set(bufnr, "n", { "q", "<esc>" }, function()
    self:destroy()
  end, opts)
end

-- Clears handlers we setup before.
function GitBlameFile:clear_handlers()
  vim.api.nvim_buf_del_keymap(self.file_bufnr, "n", "q")
  vim.api.nvim_buf_del_keymap(self.file_bufnr, "n", "<esc>")
end

-- Loads Fugit2Blame in file buffer information.
function GitBlameFile:load()
  local hunks = self:update()
  if hunks and #hunks > 0 then
    self:setup_handlers()
    self:render(hunks)
  end
end

-- Destroy all rendered information.
function GitBlameFile:destroy()
  self:clear_handlers()

  -- remove buffer variables/extmarks
  vim.api.nvim_buf_set_var(self.file_bufnr, "fugit2_blame_is_loaded", false)
  vim.api.nvim_buf_clear_namespace(self.file_bufnr, self.ns_id, 0, -1)

  -- clean object
  self.file_bufnr = nil
  self.ns_id = nil
  self._git = nil
  self._states = nil
end

-- Toggles GitBlameInformation in file buffer.
function GitBlameFile:toggle()
  local success, loaded = pcall(vim.api.nvim_buf_get_var, self.file_bufnr, "fugit2_blame_is_loaded")

  if not success or not loaded then
    self:load()
  else
    self:destroy()
  end
end

-- Refreshs a GitBlameFile in file buffer
function GitBlameFile:refresh()
  local success, loaded = pcall(vim.api.nvim_buf_get_var, self.file_bufnr, "fugit2_blame_is_loaded")

  if success and loaded then
    self:clear_handlers()
    vim.api.nvim_buf_clear_namespace(self.file_bufnr, self.ns_id, 0, -1)
  end

  self:load()
end

return GitBlameFile
