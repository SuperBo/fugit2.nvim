-- GitBlame split view

local Object = require "nui.object"
local keymap = require "nui.utils.keymap"
local table_new = require "table.new"
local uv = vim.uv or vim.loop

local event = require("nui.utils.autocmd").event
local notifier = require "fugit2.notifier"
local utils = require "fugit2.utils"

local WIDTH = 45

---@class Fugit2GitBlameHunk
---@field commit GitCommit?
---@field author_name string
---@field author_email string
---@field oid string
---@field date osdate?
---@field message string
---@field num_lines integer
---@field start_linenr integer
---@field orig_path string?

---@class Fugit2GitBlameView
---@field ns_id integer namespace number
---@field repo GitRepository git repository
local GitBlame = Object "Fugit2GitBlameView"

-- Inits GitBlameView object
---@param ns_id integer namespace number
---@param repo GitRepository git repository
---@param file_bufnr integer file buffer
function GitBlame:init(ns_id, repo, file_bufnr)
  self.ns_id = ns_id
  self.repo = repo
  self.file_bufnr = file_bufnr

  local file_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(file_bufnr), ":.")

  self._git = {
    file_path = file_path,
    commits = {} --[[@as { [string]: GitCommit }]],
    hunks = {} --[[@as Fugit2GitBlameHunk[] ]],
  }

  -- TODO: concat git_path_to_bufname
  local buf_name = "Fugit2GitBlame:" .. file_path

  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":.")
    if name == buf_name then
      self.bufnr = b
      return
    end
  end

  if not self.bufnr then
    local bufnr = vim.api.nvim_create_buf(true, true)
    self.bufnr = bufnr
    vim.api.nvim_buf_set_lines(bufnr, 0, 2, false, {
      "❯ Fugit2Blame Info",
      "",
    })
    vim.api.nvim_buf_set_name(bufnr, buf_name)
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  end

  self:setup_handlers()

  self:start_timer()
  self:update()
end

---@param repo GitRepository
---@param file_path string
---@param commits { [string]: GitCommit }
---@param blame GitBlame
---@return Fugit2GitBlameHunk[]
---@return integer total_lines
local function git_blame_to_hunks(repo, file_path, commits, blame)
  local nhunks = blame:nhunks()

  ---@type Fugit2GitBlameHunk[]
  local hunks = table_new(nhunks, 0)
  local total_lines = 0

  for i = 0, nhunks - 1 do
    local git_hunk = blame:hunk(i)
    if not git_hunk then
      goto add_hunk_continue
    end

    total_lines = total_lines + git_hunk.num_lines

    local author_signature = git_hunk:final_signature()
    local orig_path = git_hunk:orig_path()
    local oid = git_hunk:final_commit_id()

    local msg, commit, date, err
    local commit_key = oid:tostring(10)

    if commit_key == "0000000000" then
      -- null commit
      msg = "Uncommitted changes"
    else
      commit = commits[commit_key]
      if not commit then
        commit, err = repo:commit_lookup(oid)
        commits[commit_key] = commit
      end

      if not commit then
        notifier.error("Failed to get commit " .. oid:tostring(8), err)
        msg = "Not found commit"
      else
        msg = commit:summary():sub(1, 40)
        date = commit:time()
      end
    end

    ---@type Fugit2GitBlameHunk
    local h = {
      commit = commit,
      oid = commit_key:sub(1, 8),
      author_name = author_signature and author_signature:name() or "You",
      author_email = author_signature and author_signature:email() or "You",
      message = msg,
      num_lines = git_hunk.num_lines,
      start_linenr = git_hunk.final_start_line_number,
      orig_path = orig_path ~= file_path and orig_path or nil,
      date = date,
    }
    hunks[i + 1] = h

    ::add_hunk_continue::
  end

  return hunks, total_lines
end

--- Start timer
function GitBlame:start_timer()
  local timer, tick = uv.new_timer(), 0
  if not timer then
    return
  end

  self.timer = timer
  local bufnr = self.bufnr

  timer:start(0, 100, function()
    local idx = 1 + (tick % #utils.LOADING_CHARS)
    local char = utils.LOADING_CHARS[idx]
    tick = tick + 1

    vim.schedule(function()
      vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { char })
    end)
  end)
end

-- Updates buffer info
function GitBlame:update()
  local lines = vim.api.nvim_buf_get_lines(self.file_bufnr, 0, -1, false)
  local contents = table.concat(lines, "\n") .. "\n"

  ---@type GitBlameOptions
  local opts = {}

  local git = self._git
  local path = git.file_path
  self.repo:blame_file_async(git.file_path, opts, function(blame, err)
    if self.timer then
      self.timer:stop()
      self.timer:close()
      self.timer = nil
    end

    if not blame then
      notifier.error("Can't get git blame for file " .. path, err)
      return
    end

    if not self.bufnr then
      -- blame is closed while loading
      return
    end

    local b
    b, err = blame:blame_buffer(contents)
    if not b then
      notifier.error("Can't blame buffer", err)
      return
    end

    git.hunks, git.num_lines = git_blame_to_hunks(self.repo, git.path, git.commits, b)

    vim.schedule(function()
      self:render()
    end)
  end)
end

---@param buf string buffer content
function GitBlame:update_buffer(buf)
  local git = self._git

  if not git.blame then
    return
  end

  local blame, err = git.blame:blame_buffer(buf)
  if not blame then
    notifier.error("Can't get git blame for buffer", err)
    return
  end

  git.hunks, git.num_lines = git_blame_to_hunks(self.repo, git.path, git.commits, blame)
end

-- Renders GitBlame buffer
function GitBlame:render()
  local git = self._git
  local bufnr = self.bufnr

  -- clear buffer
  local num_lines = vim.api.nvim_buf_line_count(bufnr)
  if num_lines > git.num_lines then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  end

  -- render
  for _, hunk in ipairs(git.hunks) do
    local lines = table_new(hunk.num_lines, 0)
    lines[1] = hunk.message
    for i = 2, hunk.num_lines do
      lines[i] = "|"
    end

    local end_linenr = hunk.start_linenr + hunk.num_lines - 1
    vim.api.nvim_buf_set_lines(bufnr, hunk.start_linenr - 1, end_linenr, false, lines)
  end

  -- lock buffer edit
  vim.api.nvim_buf_set_option(bufnr, "readonly", true)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

-- Mount this buffer as split
function GitBlame:mount()
  local winid = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(0)
  self.file_winid = winid

  vim.schedule(function()
    -- move cursor to start of file
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    if #vim.api.nvim_list_wins() > 1 then
      -- turn off other splits
      vim.cmd.only { bang = true }
    end
    -- split at left
    vim.cmd(string.format("leftabove %dvsplit", WIDTH))
    self.winid = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(self.bufnr)
    vim.api.nvim_win_set_option(0, "wrap", false)
    vim.api.nvim_win_set_option(0, "number", false)
    vim.api.nvim_win_set_option(0, "signcolumn", "no")
    vim.api.nvim_win_set_option(0, "scrollbind", true)
    vim.api.nvim_win_set_option(0, "cursorbind", true)
    -- switch back
    vim.api.nvim_win_set_option(winid, "wrap", false)
    vim.api.nvim_win_set_option(winid, "scrollbind", true)
    vim.api.nvim_win_set_option(winid, "cursorbind", true)
    -- move cursor back
    vim.api.nvim_win_set_cursor(winid, cursor)
    vim.api.nvim_set_current_win(winid)
  end)
end

function GitBlame:unmount()
  if self.timer and self.timer:is_active() then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end

  if vim.api.nvim_win_is_valid(self.winid) then
    vim.api.nvim_win_close(self.winid, true)
  end

  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    local bufnr = self.bufnr
    vim.schedule(function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end

  self.bufnr = nil
  self._git = {}
  self.repo = nil
end

-- Setup key binding and events
function GitBlame:setup_handlers()
  local opts = { noremap = true, nowait = true }

  -- buf hidden event
  vim.api.nvim_create_autocmd({ event.BufHidden }, {
    buffer = self.bufnr,
    once = true,
    callback = function(ev)
      self:unmount()
    end
  })

  -- buf del event
  vim.api.nvim_create_autocmd({ event.BufDelete }, {
    buffer = self.bufnr,
    once = true,
    callback = function(ev)
      if self.file_winid and vim.api.nvim_win_is_valid(self.file_winid) then
        local winid = self.file_winid
        self.file_winid = nil
        vim.api.nvim_win_set_option(winid, "scrollbind", false)
        vim.api.nvim_win_set_option(winid, "cursorbind", false)
      end
    end,
  })

  -- quit event
  keymap.set(self.bufnr, "n", "q", function()
    self:unmount()
  end, opts)
end

return GitBlame
