---Module contains libgit2 with gpgme integration

local uv = vim.loop
local PlenaryJob = require "plenary.job"

local gpgme = require "fugit2.gpgme"
local utils = require "fugit2.utils"

local M = {}

---@param keyid string
---@return boolean whether is literal key
---@return string key
local function is_literal_ssh_key(keyid)
  if vim.startswith(keyid, "key::") then
    return true, keyid:sub(6)
  elseif vim.startswith(keyid, "ssh-") then
    return true, keyid
  end

  return false, keyid
end

---@param keyid string?
---@return GPGmeContext?
---@return integer error_code
---@return string error_message
local function create_gpgme_context(keyid)
  local context, err = gpgme.new_context()
  if not context then
    return nil, err, "Failed to create GPGme context"
  end

  context:set_amor(true)

  if keyid then
    local key
    key, err = context:get_key(keyid, true)
    if key then
      err = context:add_signer(key)
      if err ~= 0 then
        return nil, err, "Failed to add gpg key " .. keyid
      end
    else
      return nil, err, "Failed to get gpg key " .. keyid
    end
  end

  return context, 0, ""
end

---@param buf string
---@param keyid string signing_key
---@return string? signed
---@return integer err
---@return string err_msg
local function sign_buffer_ssh(buf, keyid)
  local key_file, err_msg, err_name

  local is_literal, key = is_literal_ssh_key(keyid)
  if is_literal then
    -- make tmp file
    local path, nbytes
    key_file, path, err_name = uv.fs_mkstemp(utils.TMPDIR .. ".git_signing_key_tmpXXXXXX")
    if not key_file then
      return nil, 0, "Can't create temp file " .. err_name
    end

    nbytes, err_msg, err_name = uv.fs_write(key_file, key, 0)
    if not nbytes then
      uv.fs_close(key_file)
      os.remove(path)
      return nil, 0, "Can't write to temp file " .. err_name
    end

    keyid = path
  end

  local ssh_keygen_args = { "-Y", "sign", "-n", "git", "-f", keyid }
  if is_literal then
    ssh_keygen_args[#ssh_keygen_args + 1] = "-U"
  end

  local job = PlenaryJob:new {
    command = "ssh-keygen",
    args = ssh_keygen_args,
    enable_recording = true,
    writer = buf,
  }
  local result, err = job:sync(2000, 200) -- wait upto 2 seconds

  if key_file then
    uv.fs_close(key_file)
    os.remove(keyid)
  end

  if err ~= 0 then
    result = job:stderr_result()
    local stderr = #result > 0 and result[1] or ""
    return nil, err, stderr
  end

  return table.concat(result, "\n"), 0, ""
end

---@param repo GitRepository
---@param commit_content string
---@param gpg_sign string
---@param msg string
---@return GitObjectId?
---@return integer err
---@return string err_msg
local function create_commit_with_sign(repo, commit_content, gpg_sign, msg)
  local commit_id, head, err
  commit_id, err = repo:create_commit_with_signature(commit_content, gpg_sign, nil)
  if not commit_id then
    return nil, err, "Failed to create commit with sign"
  end

  head, err = repo:head()
  if not head then
    return nil, err, "Failed to get git head"
  end

  _, err = head:set_target(commit_id, utils.lines_head(msg))
  if err ~= 0 then
    return nil, err, "Failed to set head to new commit"
  end

  return commit_id, 0, ""
end

---@param repo GitRepository
---@param context GPGmeContext
---@param commit_content string
---@param msg string
---@return GitObjectId?
---@return integer err
---@return string err_msg
local function create_commit_with_context(repo, context, commit_content, msg)
  local gpg_sign, err = gpgme.sign_string_detach(context, commit_content)
  if not gpg_sign then
    return nil, err, "Failed to sign commit"
  end

  return create_commit_with_sign(repo, commit_content, gpg_sign, msg)
end

---@param repo GitRepository
---@param commit_content string
---@param msg string
---@param keyid string
---@return GitObjectId?
---@return integer err
---@return string err_msg
local function create_commit_with_ssh(repo, commit_content, msg, keyid)
  local ssh_sign, err, err_msg = sign_buffer_ssh(commit_content, keyid)
  if not ssh_sign then
    return nil, err, "Failed to sign commit with ssh, " .. err_msg
  end

  return create_commit_with_sign(repo, commit_content, ssh_sign, msg)
end

-- Creates commit with gpg signing
---@param repo GitRepository
---@param index GitIndex
---@param signature GitSignature
---@param msg string commit message
---@param use_ssh boolean,
---@param keyid string? signing key id
---@return GitObjectId?
---@return integer err_code
---@return string err_msg
function M.create_commit_gpg(repo, index, signature, msg, use_ssh, keyid)
  local context, commit_content, err, err_msg

  if use_ssh and not keyid then
    return nil, -1, "user.signingkey is need when gpg.format is ssh"
  end

  if not use_ssh then
    context, err, err_msg = create_gpgme_context(keyid)
    if not context then
      return nil, err, err_msg
    end
  end

  commit_content, err = repo:create_commit_content(index, signature, msg)
  if not commit_content then
    return nil, err, "Failed to create git commit content"
  end

  if not use_ssh and context then
    return create_commit_with_context(repo, context, commit_content, msg)
  elseif keyid then
    return create_commit_with_ssh(repo, commit_content, msg, keyid)
  end

  return nil, -1, "unknown error"
end

-- Amend commit with gpg signing
---@param repo GitRepository
---@param index GitIndex?
---@param signature GitSignature?
---@param msg string? commit message
---@param use_ssh boolean use ssh signing instead of gpg
---@param keyid string? signing key id
---@return GitObjectId?
---@return integer err_code
---@return string err_msg
function M.amend_commit_gpg(repo, index, signature, msg, use_ssh, keyid)
  local context, commit_content, err, err_msg

  if use_ssh and not keyid then
    return nil, -1, "user.signingkey is need when gpg.format is ssh"
  end

  if not use_ssh then
    context, err, err_msg = create_gpgme_context(keyid)
    if not context then
      return nil, err, err_msg
    end
  end

  commit_content, msg, err = repo:amend_commit_content(index, signature, signature, msg)
  if not commit_content or not msg then
    return nil, err, "Failed to create git commit content"
  end

  if not use_ssh and context then
    return create_commit_with_context(repo, context, commit_content, msg)
  elseif keyid then
    return create_commit_with_ssh(repo, commit_content, msg, keyid)
  end

  return nil, -1, "unknown error"
end

-- Rewords commit with gpg signing
---@param repo GitRepository
---@param signature GitSignature?
---@param msg string? commit message
---@param use_ssh boolean use ssh signing instead of gpg
---@param keyid string? signing key id
---@return GitObjectId?
---@return integer err_code
---@return string err_msg
function M.reword_commit_gpg(repo, signature, msg, use_ssh, keyid)
  return M.amend_commit_gpg(repo, nil, signature, msg, use_ssh, keyid)
end

-- Extend commit with gpg signing
---@param repo GitRepository
---@param index GitIndex
---@param use_ssh boolean use ssh signing instead of gpg
---@param keyid string? signing key id
---@return GitObjectId?
---@return integer err_code
---@return string err_msg
function M.extend_commit_gpg(repo, index, use_ssh, keyid)
  return M.amend_commit_gpg(repo, index, nil, nil, use_ssh, keyid)
end

return M
