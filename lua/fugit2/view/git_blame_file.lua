-- GitBlame inside view using virtual texts

local NuiLine = require "nui.line"
local NuiPopup = require "nui.popup"
local NuiText = require "nui.text"
local Object = require "nui.object"
local Path = require "plenary.path"
local PlenaryJob = require "plenary.job"
local keymap = require "nui.utils.keymap"
local strings = require "plenary.strings"
local event = require("nui.utils.autocmd").event

local blame = require "fugit2.core.blame"
local config = require "fugit2.config"
local notifier = require "fugit2.notifier"
local pendulum = require "fugit2.core.pendulum"
local utils = require "fugit2.utils"

---@alias Fugit2GitBlameRange {start: integer, num: integer}

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
    commits = {} --[[@as {[string]: Fugit2GitBlameCommit}]],
    commit_line_range = {} --[[@as {[string]: Fugit2GitBlameRange[] }]],
  }

  self._states = {
    last_linenr = -1,
  }
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

  local total_lines = 0
  local offsets = utils.list_new(#hunks)
  local commit_range = {} --[[@as {[string]: Fugit2GitBlameRange[] }]]
  local author_len = 4

  for i, h in ipairs(hunks) do
    offsets[i] = total_lines + 1
    total_lines = total_lines + h.num_lines
    author_len = math.max(author_len, h.author_name:len())

    local ranges = commit_range[h.oid]
    if not ranges then
      commit_range[h.oid] = { { start = h.orig_start_linenr, num = h.num_lines } }
    else
      ranges[#ranges + 1] = { start = h.orig_start_linenr, num = h.num_lines }
    end
  end

  git.hunk_offsets = offsets
  git.num_lines = total_lines
  git.author_len = author_len
  git.hunks = hunks
  git.commit_line_range = commit_range

  return hunks
end

-- Renders hunks as virtual text in to file buffer.
---@param hunks Fugit2GitBlameHunk[]
function GitBlameFile:render(hunks)
  local bufnr = self.file_bufnr
  local ns_id = self.ns_id
  local nlines = vim.api.nvim_buf_line_count(bufnr)

  local author_len = self._git.author_len
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
    })

    if hunk.num_lines > 1 then
      virt_text[3][1] = "│"
      for i = 1, hunk.num_lines - 2 do
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, hunk.start_linenr + i - 1, 0, {
          virt_text_pos = "inline",
          virt_text = virt_text,
          virt_text_repeat_linebreak = true,
          priority = virt_text_priority,
        })
      end

      virt_text[3][1] = "┘"
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, hunk.start_linenr + hunk.num_lines - 2, 0, {
        virt_text_pos = "inline",
        virt_text = virt_text,
        virt_text_repeat_linebreak = true,
        priority = virt_text_priority,
      })
    end
  end
end

-- Toggles blame popup.
function GitBlameFile:toggle_blame_popup()
  local states = self._states

  if states.popup then
    states.popup:unmount()
    states.popup = nil
    vim.api.nvim_del_autocmd(states.cursor_move_handler)
    states.cursor_move_handler = nil
  else
    self:show_blame_popup()
  end
end

-- Shows commit and hunk details of current line
function GitBlameFile:show_blame_popup()
  local width = config.get_number "blame_info_width" or 60
  local height = config.get_number "blame_info_height" or 10
  local blame_detail = NuiPopup {
    ns_id = self.ns_id,
    enter = false,
    focusable = true,
    position = {
      row = 1,
      col = 2,
    },
    relative = "cursor",
    anchor = "SW",
    size = {
      width = width,
      height = height,
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      wrap = false,
    },
    buf_options = {
      -- modifiable = false,
      -- readonly = true,
      swapfile = false,
      buftype = "nofile",
    },
    border = {
      style = "rounded",
      padding = { top = 0, bottom = 0, left = 1, right = 1 },
      text = {
        top = NuiText("   Commit ", "Fugit2FloatTitle"),
        top_align = "left",
      },
    },
  }

  local states = self._states
  states.popup = blame_detail

  self:render_blame_popup(blame_detail.bufnr, width, nil)

  local exit_fn = function()
    vim.api.nvim_del_autocmd(states.cursor_move_handler)
    states.cursor_move_handler = nil
    states.popup = nil
    blame_detail:unmount()
  end
  blame_detail:map("n", { "q", "<esc>" }, exit_fn, { noremap = true, nowait = true })
  blame_detail:on(event.BufLeave, exit_fn, { once = true })

  states.cursor_move_handler = vim.api.nvim_create_autocmd({ event.CursorMoved, event.WinScrolled }, {
    group = "Fugit2",
    buffer = self.file_bufnr,
    desc = "Update GitBlame popup when move cursor",
    callback = self:blame_popup_move_handler(blame_detail),
  })

  blame_detail:mount()
end

---@param popup NuiPopup
function GitBlameFile:blame_popup_move_handler(popup)
  local states = self._states
  local hunk_offsets = self._git.hunk_offsets
  local num_lines = self._git.num_lines

  return function(ev)
    if not ev or ev.event == "WinScrolled" then
      -- WinScrolled
      popup:update_layout()
      return
    end

    local row = vim.api.nvim_win_get_cursor(0)[1]
    if row == states.last_linenr then
      popup:update_layout()
      return
    end
    states.last_linenr = row

    if states.last_hunk_offset then
      if row >= states.last_hunk_offset and row < (states.last_hunk_offset_end or (num_lines + 1)) then
        -- same hunk
        popup:update_layout()
        return
      end
    end

    -- local hunk_idx, offset = utils.get_hunk(hunk_offsets, row)
    local width = popup.win_config.width

    self:render_blame_popup(popup.bufnr, width, row)
    popup:update_layout()
  end
end

-- Renders related patch hunk of this blame hunk.
---@param bufnr integer
---@param ns_id integer
---@param render_start_linenr integer
---@param hunk_start_line integer blame hunk start line number
---@param hunk_num_lines integer blame hunk num lines
---@param commit Fugit2GitBlameCommit
local function blame_popup_render_hunk(bufnr, ns_id, render_start_linenr, hunk_start_line, hunk_num_lines, commit)
  local hunk, lines = blame.find_intersect_hunk(commit.hunks, commit.patch, hunk_start_line, hunk_num_lines)
  if not hunk or not lines then
    -- not found intersect hunk
    return
  end

  for i, l in ipairs(lines) do
    local hl_group = ""
    local char = l:sub(1, 1)
    if char == "+" then
      hl_group = "diffAdded"
    elseif char == "-" then
      hl_group = "diffRemoved"
    end
    local line = NuiLine { NuiText(l, hl_group) }
    line:render(bufnr, ns_id, render_start_linenr + i - 1)
  end
end

-- Renders blame details in popup
---@param bufnr integer buffer number of blame popup
---@param width integer popup width
---@param row integer? optional row
function GitBlameFile:render_blame_popup(bufnr, width, row)
  local offsets = self._git.hunk_offsets
  if not row then
    row = vim.api.nvim_win_get_cursor(0)[1]
  end
  local hunk_idx, hunk_offset = utils.get_hunk(offsets, row)
  if not hunk_idx then
    return
  end

  local hunk = self._git.hunks[hunk_idx] --[[@as Fugit2GitBlameHunk? ]]
  if not hunk then
    return
  end

  local git = self._git
  local commit = git.commits[hunk.oid] --[[@as Fugit2GitBlameCommit?]]
  if not commit then
    commit = blame.blame_commit_detail(git.repo, hunk.oid, hunk.orig_path, git.commit_line_range[hunk.oid])
    git.commits[hunk.oid] = commit
  end

  local ns_id = self.ns_id
  local opts = { buf = bufnr }
  vim.api.nvim_set_option_value("modifiable", true, opts)
  vim.api.nvim_set_option_value("readonly", false, opts)

  local header = NuiLine { NuiText(hunk.oid:sub(1, 8) .. " ", "Fugit2ObjectId") }
  header:append(utils.message_title_prettify(hunk.message))
  header:render(bufnr, ns_id, 1)

  -- local split = NuiLine { NuiText(" ------", "Fugit2ObjectId") }
  local author_text = "  Author "
  local half_width = math.floor((width - strings.strdisplaywidth(author_text)) / 2)
  local split_text_left = string.rep("─", half_width)
  local split_text = split_text_left .. author_text .. split_text_left
  local split = NuiLine { NuiText(split_text, "Fugit2ObjectId") }
  split:render(bufnr, ns_id, 2)

  local author = NuiLine {
    NuiText(hunk.author_name, "Fugit2Author"),
  }
  if hunk.author_email then
    author:append(" " .. hunk.author_email, "Fugit2AuthorEmail")
  end
  author:render(bufnr, ns_id, 3)

  local committer = NuiLine {
    NuiText(hunk.committer_name, "Fugit2Author"),
  }
  if hunk.committer_email then
    committer:append " "
    committer:append(hunk.committer_email, "Fugit2AuthorEmail")
  end
  committer:append " committed on "
  committer:append(pendulum.datetime_tostring(hunk.date, true), "Fugit2BlameDate")
  committer:render(bufnr, ns_id, 4)

  local hunk_header = "  Changes "
  half_width = math.floor((width - strings.strdisplaywidth(hunk_header)) / 2)
  split_text_left = string.rep("─", half_width)
  split_text = split_text_left .. hunk_header .. split_text_left
  split = NuiLine { NuiText(split_text, "Fugit2ObjectId") }
  split:render(bufnr, ns_id, 5)

  -- clear patch info
  vim.api.nvim_buf_set_lines(bufnr, 6, -1, false, {})
  if commit and commit.hunks and #commit.hunks > 0 then
    blame_popup_render_hunk(bufnr, ns_id, 6, hunk.orig_start_linenr, hunk.num_lines, commit)
  end

  vim.api.nvim_set_option_value("modifiable", false, opts)
  vim.api.nvim_set_option_value("readonly", true, opts)

  -- save info into cache
  local states = self._states
  local num_lines = self._git.num_lines
  states.last_hunk_idx = hunk_idx
  states.last_hunk_offset = hunk_offset
  states.last_hunk_offset_end = hunk_idx >= #offsets and num_lines + 1 or offsets[hunk_idx + 1]
end

-- setup handlers in main buffer
function GitBlameFile:setup_handlers()
  local opts = { noremap = true, nowait = true }
  local bufnr = self.file_bufnr

  -- quit event
  keymap.set(bufnr, "n", { "q", "<esc>" }, function()
    self:destroy()
  end, opts)

  -- show detail
  keymap.set(bufnr, "n", { "c" }, function()
    self:toggle_blame_popup()
  end, opts)
end

-- Clears handlers we setup before.
function GitBlameFile:clear_handlers()
  vim.api.nvim_buf_del_keymap(self.file_bufnr, "n", "q")
  vim.api.nvim_buf_del_keymap(self.file_bufnr, "n", "<esc>")
  vim.api.nvim_buf_del_keymap(self.file_bufnr, "n", "c")
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

  -- unmount blame popup
  if self._states.popup then
    self._states.popup:unmount()
  end

  -- remove buffer variables/extmarks/autocmd
  vim.api.nvim_buf_set_var(self.file_bufnr, "fugit2_blame_is_loaded", false)
  vim.api.nvim_buf_clear_namespace(self.file_bufnr, self.ns_id, 0, -1)
  vim.api.nvim_clear_autocmds {
    event = { event.BufWritePost, event.CursorMoved, event.WinScrolled },
    buffer = self.file_bufnr,
    group = "Fugit2",
  }

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
