---Module contains libgit2 with gpgme integration

local gpgme = require "fugit2.gpgme"
local utils = require "fugit2.utils"

local M = {}

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

  local commit_id, head
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

-- Creates commit with gpg signing
---@param repo GitRepository
---@param index GitIndex
---@param signature GitSignature
---@param msg string commit message
---@param keyid string? signing key id
---@return GitObjectId?
---@return integer err_code
---@return string err_msg
function M.create_commit_gpg(repo, index, signature, msg, keyid)
  local context, err, err_msg = create_gpgme_context(keyid)
  if not context then
    return nil, err, err_msg
  end

  local commit_content
  commit_content, err = repo:create_commit_content(index, signature, msg)
  if not commit_content then
    return nil, err, "Failed to create commit content"
  end

  return create_commit_with_context(repo, context, commit_content, msg)
end

-- Amend commit with gpg signing
---@param repo GitRepository
---@param index GitIndex?
---@param signature GitSignature?
---@param msg string? commit message
---@param keyid string? signing key id
---@return GitObjectId?
---@return integer err_code
---@return string err_msg
function M.amend_commit_gpg(repo, index, signature, msg, keyid)
  local context, err, err_msg = create_gpgme_context(keyid)
  if not context then
    return nil, err, err_msg
  end

  local commit_content
  commit_content, msg, err = repo:amend_commit_content(index, signature, signature, msg)
  if not commit_content or not msg then
    return nil, err, "Failed to create commit content"
  end

  return create_commit_with_context(repo, context, commit_content, msg)
end

-- Rewords commit with gpg signing
---@param repo GitRepository
---@param signature GitSignature?
---@param msg string? commit message
---@param keyid string? signing key id
---@return GitObjectId?
---@return integer err_code
---@return string err_msg
function M.reword_commit_gpg(repo, signature, msg, keyid)
  return M.amend_commit_gpg(repo, nil, signature, msg, keyid)
end

-- Extend commit with gpg signing
---@param repo GitRepository
---@param index GitIndex
---@param keyid string? signing key id
---@return GitObjectId?
---@return integer err_code
---@return string err_msg
function M.extend_commit_gpg(repo, index, keyid)
  return M.amend_commit_gpg(repo, index, nil, nil, keyid)
end

return M
