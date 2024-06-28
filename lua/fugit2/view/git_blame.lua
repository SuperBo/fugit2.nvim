-- GitBlame split view

local Object = require "nui.object"
local keymap = require "nui.utils.keymap"
local table_new = require "table.new"
local uv = vim.uv or vim.loop
local NuiLine = require "nui.line"
local NuiText = require "nui.text"
local Path = require "plenary.path"
local PlenaryJob = require "plenary.job"
local strings = require "plenary.strings"

local event = require("nui.utils.autocmd").event
local blame = require "fugit2.core.blame"
local notifier = require "fugit2.notifier"
local utils = require "fugit2.utils"

local WIDTH = 45
local HEADER_START = "▇ "

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
  self.file_bufnr = file_bufnr

  local file_path = Path:new(vim.fn.fnameescape(vim.api.nvim_buf_get_name(file_bufnr)))
  local git_path = vim.fn.fnamemodify(repo:repo_path(), ":p:h:h")

  self._git = {
    file_path = file_path:make_relative(git_path),
    path = git_path,
    commits = {} --[[@as { [string]: GitCommit }]],
    hunks = {} --[[@as Fugit2GitBlameHunk[] ]],
    hunk_offsets = {} --[[@as integer[] ]],
    authors_map = {} --[[@as {[string]: integer} ]],
  }

  local buf_name = "Fugit2GitBlame:" .. tostring(file_path)

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
    vim.api.nvim_buf_set_option(bufnr, "filetype", "fugit2-blame")
  end

  self:setup_handlers()

  self:start_timer()
  self:update()
  self:render()
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
      if self.timer then
        vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { char })
      end
    end)
  end)
end

-- Updates buffer info
function GitBlame:update()
  -- local lines = vim.api.nvim_buf_get_lines(self.file_bufnr, 0, -1, false)
  -- local contents = table.concat(lines, "\n") .. "\n"
  local git_path = self._git.path
  local git = self._git

  local job = PlenaryJob:new {
    command = "git",
    args = { "blame", "--date=unix", "--porcelain", self._git.file_path },
    cwd = git_path,
    enable_recording = true,
  }
  local result, err = job:sync(5000, 200) -- wait till 3 seconds

  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end

  if err ~= 0 then
    result = job:stderr_result()
    local stderr = #result > 0 and result[1] or ""
    notifier.error("git blame error, " .. stderr, err)
    return
  end

  local hunks = blame.parse_git_blame_porcelain_lines(result)

  local authors_map = {}
  local total_lines = 0
  local offsets = table_new(#hunks, 0)

  for i, h in ipairs(hunks) do
    authors_map[h.author_name] = 1
    offsets[i] = total_lines + 1
    total_lines = total_lines + h.num_lines
  end

  git.hunks = hunks
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
end

---@param hunk Fugit2GitBlameHunk
---@param now osdateparam
---@param authors_map { [string]: integer }
---@return NuiLine header_line
---@return integer age_colore
local function prepare_blame_header(hunk, now, authors_map)
  local time_ago = "now"
  local age_color = 10 -- latest

  if hunk.date then
    time_ago, age_color = blame.blame_time(hunk.date, now)
  end

  local author_idx = (authors_map[hunk.author_name] or 0) % 9 + 1
  local content_len = 15 + strings.strdisplaywidth(hunk.author_name) + 1
  local author_width = WIDTH - content_len
  local message = utils.message_title_prettify(hunk.message:sub(1, author_width))

  local line = NuiLine {
    NuiText(HEADER_START, "Fugit2BlameAge" .. age_color),
    NuiText(strings.align_str(time_ago .. " ", 13, true), "Fugit2BlameDate"),
    NuiText(hunk.author_name .. " ", "Fugit2Branch" .. author_idx),
  }
  line:append(message)
  return line, age_color
end

-- Renders GitBlame buffer
function GitBlame:render()
  local git = self._git
  local bufnr = self.bufnr
  local ns_id = self.ns_id
  local authors_map = git.authors_map

  -- unlock buffer edit
  vim.api.nvim_buf_set_option(bufnr, "readonly", false)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

  -- clear buffer
  local num_lines = vim.api.nvim_buf_line_count(bufnr)
  if num_lines > git.num_lines then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  end

  -- render
  local now = os.date "*t" --[[@as osdateparam]]
  for _, hunk in ipairs(git.hunks) do
    local header, age_color = prepare_blame_header(hunk, now, authors_map)
    header:render(bufnr, ns_id, hunk.start_linenr)

    if hunk.num_lines > 1 then
      local end_linenr = hunk.start_linenr + hunk.num_lines

      -- empty lines
      if hunk.num_lines > 1 then
        local lines = utils.list_init("│", hunk.num_lines - 2)
        lines[hunk.num_lines - 1] = "└"
        vim.api.nvim_buf_set_lines(bufnr, hunk.start_linenr, end_linenr - 1, false, lines)
      end

      vim.api.nvim_buf_set_extmark(bufnr, ns_id, hunk.start_linenr, 0, {
        end_row = hunk.start_linenr + hunk.num_lines - 1,
        end_col = 0,
        hl_group = "Fugit2BlameAge" .. age_color,
      })
    end
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

  -- clear auto command in main window
  vim.api.nvim_clear_autocmds {
    event = event.BufWritePost,
    buffer = self.file_bufnr,
    group = "Fugit2",
  }

  vim.api.nvim_create_autocmd(event.BufWritePost, {
    group = "Fugit2",
    buffer = self.file_bufnr,
    desc = "Update GitBlame buffer when finished writing file",
    callback = function()
      self:update()
      self:render()
    end,
  })

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
    vim.api.nvim_win_set_option(0, "foldcolumn", "0")
    vim.api.nvim_win_set_option(0, "scrollbind", true)
    vim.api.nvim_win_set_option(0, "cursorbind", true)
    -- original buffer
    vim.api.nvim_win_set_option(winid, "wrap", false)
    vim.api.nvim_win_set_option(winid, "scrollbind", true)
    vim.api.nvim_win_set_option(winid, "cursorbind", true)
    vim.api.nvim_win_set_cursor(winid, cursor)
    -- vim.api.nvim_set_current_win(winid)
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

---Gets current hunk based on current cursor position
---@return integer hunk_index
---@return integer hunk_offset
---@return integer cursor_row
---@return integer cursor_col
function GitBlame:get_current_hunk()
  local cursor = vim.api.nvim_win_get_cursor(self.winid)
  local index, offset = utils.get_hunk(self._git.hunk_offsets, cursor[1])

  return index, offset, cursor[1], cursor[2]
end

function GitBlame:next_hunk()
  local hunk_idx, _, row, col = self:get_current_hunk()
  local new_row = self._git.hunk_offsets[hunk_idx + 1]
  if new_row > row then
    vim.api.nvim_win_set_cursor(self.winid, { new_row, col })
  end
end

function GitBlame:prev_hunk()
  local hunk_idx, hunk_offset, row, col = self:get_current_hunk()
  local new_row = hunk_offset
  if hunk_offset == row then
    new_row = self._git.hunk_offsets[math.max(hunk_idx - 1, 1)]
  end
  vim.api.nvim_win_set_cursor(self.winid, { new_row, col })
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
    end,
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
        vim.api.nvim_clear_autocmds {
          event = event.BufWritePost,
          buffer = self.file_bufnr,
          group = "Fugit2",
        }
      end
    end,
  })

  -- quit event
  keymap.set(self.bufnr, "n", { "q", "<esc>" }, function()
    self:unmount()
  end, opts)

  -- jump events
  keymap.set(self.bufnr, "n", { "J", "]c" }, function()
    self:next_hunk()
  end, opts)
  keymap.set(self.bufnr, "n", { "K", "[c" }, function()
    self:prev_hunk()
  end, opts)
end

return GitBlame
