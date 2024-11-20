---@enum Fugit2GitHookNames
local GitHookNames = {
  APPLYPATCH_MSG = "applypatch-msg",
  PRE_APPLYPATCH = "pre-applypatch",
  POST_APPLYPATCH = "post-applypatch",
  PRE_MERGE_COMMIT = "pre-merge-commit",
  PREPARE_COMMIT_MSG = "prepare-commit-msg",
  COMMIT_MSG = "commit-msg",
  POST_COMMIT = "post-commit",
  PRE_REBASE = "pre-rebase",
  POST_CHECKOUT = "post-checkout",
  POST_MERGE = "post-merge",
  PRE_PUSH = "pre-push",
  PRE_RECEIVE = "pre-receive",
  PRE_COMMIT = "pre-commit",
  PROC_RECEIVE = "proc-receive",
  POST_RECEIVE = "post-receive",
  POST_UPDATE = "post-update",
  REFERENCE_TRANSACTION = "reference-transaction",
  PUSH_TO_CHECKOUT = "push-to-checkout",
  PRE_AUTO_GC = "pre-auto-gc",
  POST_REWRITE = "post-rewrite",
  SENDEMAIL_VALIDATE = "sendemail-validate",
  FSMONITOR_WATCHMAN = "fsmonitor-watchman",
  P4_CHANGELIST = "p4-changelist",
  P4_PREPARE_CHANGELIST = "p4-prepare-changelist",
  P4_POST_CHANGELIST = "p4-post-changelist",
  P4_PRE_SUBMIT = "p4-pre-submit",
  POST_INDEX_CHANGE = "post-index-change",
}

local M = {}

M.NAMES = GitHookNames

-- Get Hook path for a given hook
---@param path Path git_hooks_path
---@param hook_name Fugit2GitHookNames
---@return string? hook_exec Hook executable if exist
function M.get_hook_exec(path, hook_name)
  local hook = path / hook_name
  if hook:is_file() then
    return hook:make_relative()
  end
  return nil
end

return M
