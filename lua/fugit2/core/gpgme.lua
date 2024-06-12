local ffi = require "ffi"

local char_array = ffi.typeof "char[?]"

local gpgme_library_path = "gpgme"

-- Loads GPGme C library
---@return ffi.cdata*
---@return table
local function load_gpgme()
  ffi.cdef [[
    typedef unsigned int gpgme_error_t;
    typedef struct gpgme_context* gpgme_ctx_t;
    typedef struct gpgme_data* gpgme_data_t;

    typedef struct _gpgme_subkey {
      struct _gpgme_subkey *next;
      unsigned int revoked : 1;
      unsigned int expired : 1;
      unsigned int disabled : 1;
      unsigned int invalid : 1;
      unsigned int can_encrypt : 1;
      unsigned int can_sign : 1;
      unsigned int can_certify : 1;
      unsigned int secret : 1;
      unsigned int can_authenticate : 1;
      unsigned int is_qualified : 1;
      unsigned int is_cardkey : 1;
      unsigned int is_de_vs : 1;
      unsigned int can_renc : 1;
      unsigned int can_timestamp : 1;
      unsigned int is_group_owned : 1;
      unsigned int _unused : 17;
      unsigned int pubkey_algo;
      unsigned int length;
      char *keyid;
      char _keyid[16 + 1];
      char *fpr;
      long int timestamp;
      long int expires;
      char *card_number;
      char *curve;
      char *keygrip;
      char *v5fpr;
    };
    typedef struct _gpgme_subkey* gpgme_subkey_t;

    typedef struct _gpgme_sig_notation {
      struct _gpgme_sig_notation *next;
      char *name;
      char *value;
      int name_len;
      int value_len;
      unsigned int flags;
      unsigned int human_readable : 1;
      unsigned int critical : 1;
      int _unused : 30;
    };
    typedef struct _gpgme_sig_notation* gpgme_sig_notation_t;

    typedef struct _gpgme_key_sig {
      struct _gpgme_key_sig *next;
      unsigned int revoked : 1;
      unsigned int expired : 1;
      unsigned int invalid : 1;
      unsigned int exportable : 1;
      unsigned int _unused : 12;
      unsigned int trust_depth : 8;
      unsigned int trust_value : 8;
      unsigned int pubkey_algo;
      char *keyid;
      char _keyid[16 + 1];
      long int timestamp;
      long int expires;
      gpgme_error_t status;
      unsigned int _obsolete_class;
      char *uid;
      char *name;
      char *email;
      char *comment;
      unsigned int sig_class;
      gpgme_sig_notation_t notations;
      gpgme_sig_notation_t _last_notation;
      char *trust_scope;
    };
    typedef struct _gpgme_key_sig* gpgme_key_sig_t;



    typedef struct _gpgme_tofu_info {
      struct _gpgme_tofu_info *next;
      unsigned int validity : 3;
      unsigned int policy : 4;
      unsigned int _rfu : 25;
      unsigned short signcount;
      unsigned short encrcount;
      unsigned long signfirst;
      unsigned long signlast;
      unsigned long encrfirst;
      unsigned long encrlast;
      char *description;
    };
    typedef struct _gpgme_tofu_info* gpgme_tofu_info_t;

    typedef struct _gpgme_user_id {
      struct _gpgme_user_id *next;
      unsigned int revoked : 1;
      unsigned int invalid : 1;
      unsigned int _unused : 25;
      unsigned int origin : 5;
      unsigned int validity;
      char *uid;
      char *name;
      char *email;
      char *comment;
      gpgme_key_sig_t signatures;
      gpgme_key_sig_t _last_keysig;
      char *address;
      gpgme_tofu_info_t tofu;
      unsigned long last_update;
      char *uidhash;
    };
    typedef struct _gpgme_user_id* gpgme_user_id_t;

    typedef struct _gpgme_key {
      unsigned int _refs;
      unsigned int revoked : 1;
      unsigned int expired : 1;
      unsigned int disabled : 1;
      unsigned int invalid : 1;
      unsigned int can_encrypt : 1;
      unsigned int can_sign : 1;
      unsigned int can_certify : 1;
      unsigned int secret : 1;
      unsigned int can_authenticate : 1;
      unsigned int is_qualified : 1;
      unsigned int has_encrypt : 1;
      unsigned int has_sign : 1;
      unsigned int has_certify : 1;
      unsigned int has_authenticate : 1;
      unsigned int _unused : 13;
      unsigned int origin : 5;
      unsigned int protocol;
      char *issuer_serial;
      char *issuer_name;
      char *chain_id;
      unsigned int owner_trust;
      gpgme_subkey_t subkeys;
      gpgme_user_id_t uids;
      gpgme_subkey_t _last_subkey;
      gpgme_user_id_t _last_uid;
      unsigned int keylist_mode;
      char *fpr;
      unsigned long last_update;
    };
    typedef struct _gpgme_key* gpgme_key_t;

    typedef struct _gpgme_new_signature {
      struct _gpgme_new_signature *next;
      unsigned type;
      unsigned int pubkey_algo;
      unsigned int hash_algo;
      unsigned long _obsolete_class;
      long int timestamp;
      char *fpr;
      unsigned int _obsolete_class_2;
      unsigned int sig_class;
    };
    typedef struct _gpgme_new_signature* gpgme_new_signature_t;

    typedef struct _gpgme_invalid_key {
      struct _gpgme_invalid_key *next;
      char *fpr;
      gpgme_error_t reason;
    };
    typedef struct _gpgme_invalid_key* gpgme_invalid_key_t;

    typedef struct _gpgme_op_sign_result {
      gpgme_invalid_key_t invalid_signers;
      gpgme_new_signature_t signatures;
    };
    typedef struct _gpgme_op_sign_result* gpgme_sign_result_t;

    typedef struct _gpgme_signature {
      struct _gpgme_signature *next;
      unsigned int summary;
      char *fpr;
      gpgme_error_t status;
      gpgme_sig_notation_t notations;
      unsigned long timestamp;
      unsigned long exp_timestamp;
      unsigned int wrong_key_usage : 1;
      unsigned int pka_trust : 2;
      unsigned int chain_model : 1;
      unsigned int is_de_vs : 1;
      int _unused : 27;
      unsigned int validity;
      unsigned int validity_reason;
      unsigned int pubkey_algo;
      unsigned int hash_algo;
      char *pka_address;
      gpgme_key_t key;
    };
    typedef struct _gpgme_signature* gpgme_signature_t;

    typedef struct _gpgme_op_verify_result {
      gpgme_signature_t signatures;
      char *file_name;
      unsigned int is_mime : 1;
      unsigned int _unused : 31;
    };
    typedef struct _gpgme_op_verify_result* gpgme_verify_result_t;

    const char * gpgme_strerror(unsigned int err);
    const char * gpgme_check_version(const char *required_version);

    gpgme_error_t gpgme_new(gpgme_ctx_t *ctx);
    void gpgme_release(gpgme_ctx_t ctx);
    void gpgme_set_armor(gpgme_ctx_t ctx, int yes);
    gpgme_error_t gpgme_set_pinentry_mode(gpgme_ctx_t ctx, unsigned int mode);

    gpgme_error_t gpgme_data_new(gpgme_data_t *dh);
    gpgme_error_t gpgme_data_new_from_mem(gpgme_data_t *dh, const char *buffer, size_t size, int copy);
    void gpgme_data_release(gpgme_data_t dh);
    ssize_t gpgme_data_read(gpgme_data_t dh, void *buffer, size_t length);
    ssize_t gpgme_data_write(gpgme_data_t dh, const void *buffer, size_t size);
    int64_t gpgme_data_seek(gpgme_data_t dh, int64_t offset, int whence);

    void gpgme_key_ref(gpgme_key_t key);
    void gpgme_key_unref(gpgme_key_t key);
    gpgme_error_t gpgme_get_key(gpgme_ctx_t ctx, const char *fpr, gpgme_key_t *r_key, int secret);

    void gpgme_signers_clear(gpgme_ctx_t ctx);
    gpgme_error_t gpgme_signers_add(gpgme_ctx_t ctx, const gpgme_key_t key);
    unsigned int gpgme_signers_count(const gpgme_ctx_t ctx);
    gpgme_key_t gpgme_signers_enum(const gpgme_ctx_t ctx, int seq);

    gpgme_error_t gpgme_op_sign(gpgme_ctx_t ctx, gpgme_data_t plain, gpgme_data_t sig, int mode);
    gpgme_sign_result_t gpgme_op_sign_result(gpgme_ctx_t ctx);

    gpgme_error_t gpgme_op_verify(gpgme_ctx_t ctx, gpgme_data_t sig, gpgme_data_t signed_text, gpgme_data_t plain);
    gpgme_verify_result_t gpgme_op_verify_result(gpgme_ctx_t ctx);
  ]]

  local gpgme = ffi.load(gpgme_library_path)

  local gpgme_type = {
    gpgme_ctx_pointer = ffi.typeof "struct gpgme_context *",
    gpgme_ctx_double_pointer = ffi.typeof "struct gpgme_context *[1]",
    gpgme_data_pointer = ffi.typeof "struct gpgme_data *",
    gpgme_data_double_pointer = ffi.typeof "struct gpgme_data *[1]",
    gpgme_key_pointer = ffi.typeof "gpgme_key_t",
    gpgme_key_double_pointer = ffi.typeof "gpgme_key_t[1]",
  }

  -- Init gpgme
  gpgme.gpgme_check_version "1.18.0"

  return gpgme, gpgme_type
end

M = {}

-- A lazy placeholder for GPGme C lib
-- Only loads GPGme when called for the first time.
local lazy_C = {
  __index = function(table, key)
    local gpgme, types = load_gpgme()
    rawset(M, "C", gpgme)
    rawset(M, "types", types)

    return gpgme[key]
  end,
}
setmetatable(lazy_C, lazy_C)

-- A lazy placeholder for GPGme C types
local lazy_types = {
  __index = function(table, key)
    local gpgme, types = load_gpgme()
    rawset(M, "C", gpgme)
    rawset(M, "types", types)

    return types[key]
  end,
}
setmetatable(lazy_types, lazy_types)

M.C = lazy_C
M.types = lazy_types

-- ==================
-- | Init functions |
-- ==================

-- Inits gpgme libpath
---@param path string? optional path to libgit2 lib
function M.init(path)
  if path then
    gpgme_library_path = path
  end
end

-- ==============================
-- | GPGme error code functions |
-- ==============================

-- local GPG_ERR_SOURCE_DIM = 128
-- local GPG_ERR_CODE_DIM = 65536
-- local GPG_ERR_CODE_MASK	= GPG_ERR_CODE_DIM - 1
-- local GPG_ERR_SOURCE_SHIFT = 24
-- local GPG_ERR_SOURCE_MASK	= GPG_ERR_SOURCE_DIM - 1

-- Retrieves the error code from an error value.
---@param err integer
local function gpgme_err_code(err)
  return bit.band(err, 65535)
end

-- Retrieves the error source from an error value.
---@param err integer
local function gpgme_err_source(err)
  return bit.band(bit.rshift(err, 24), 127)
end

-- ===============
-- | GPGme enums |
-- ===============

local GPG_ERR_SYSTEM_ERROR = 32768 -- (1 << 15)

---@enum GPGME_ERROR_CODE
M.GPG_ERROR = {
  NO_ERROR = 0, -- Success
  GENERAL = 1, -- General error
  BAD_SIGNATURE = 8, -- Bad signature
  NO_PUBKEY = 9, -- No public key
  CHECKSUM = 10, -- Checksum error
  BAD_PASSPHRASE = 11, -- Bad passphrase
  CIPHER_ALGO = 12, -- Invalid cipher algorithm
  KEYRING_OPEN = 13, -- Cannot open keyring
  NO_SECKEY = 17, -- No secret key
  UNUSABLE_PUBKEY = 53, -- Unusable public key
  UNUSABLE_SECKEY = 54, -- Unusable secret key
  INV_VALUE = 55, -- Invalid value
  NO_DATA = 58, -- No data
  NOT_IMPLEMENTED = 69, -- Not implemented
  CONFLICT = 70, -- Conflicting use
  UNSUPPORTED_ALGORITHM = 84, -- Unsupported algorithm
  WRONG_KEY_USAGE = 125, -- Wrong key usage
  DECRYPT_FAILED = 152, -- Decryption failed
  NOT_OPERATIONAL = 176, -- Not operational
  EOF = 16383, -- End of file
  ENOMEM = bit.bor(GPG_ERR_SYSTEM_ERROR, 86), -- out-of-memory condition occurred.
}

---@enum GPGME_SIG_MODE
M.GPGME_SIG_MODE = {
  NORMAL = 0,
  DETACH = 1,
  CLEAR = 2,
  ARCHIVE = 4,
  FILE = 8,
}

-- ================
-- | GPGme Object |
-- ================

---@class GPGmeContext
---@field ctx ffi.cdata* GPGme struct gpgme_ctx*
local Context = {}
Context.__index = Context

---@class GPGmeData
---@field data ffi.cdata* GPGme struct gpgme_data*
local Data = {}
Data.__index = Data

---@class GPGmeKey
---@field key ffi.cdata* GPGme struct gpgme_key*
local Key = {}
Key.__index = Key

-- ===============-=========
-- | GPGme Context methods |
-- =========================

-- Inits new GGPme context
---@param gpgme_ctx ffi.cdata* gpgme_ctx pointer, own data
---@return GPGmeContext
function Context.new(gpgme_ctx)
  local ctx = { ctx = M.types.gpgme_ctx_pointer(gpgme_ctx) }
  setmetatable(ctx, Context)

  ffi.gc(ctx.ctx, M.C.gpgme_release)
  return ctx
end

---@param enable boolean
function Context:set_amor(enable)
  M.C.gpgme_set_armor(self.ctx, enable and 1 or 0)
end

---@param mode integer
---@return GPGME_ERROR_CODE
function Context:set_pinetry_mode(mode)
  return gpgme_err_code(M.C.gpgme_set_pinentry_mode(self.ctx, mode))
end

-- Adds the key key to the list of signers in the context.
---@param key GPGmeKey
---@return GPGME_ERROR_CODE err gpgme_err_code
function Context:add_signer(key)
  local err = M.C.gpgme_signers_add(self.ctx, key.key)
  return gpgme_err_code(err)
end

-- Returns the number of signer keys in the context.
---@return integer num_signers
function Context:count_signers()
  return M.C.gpgme_signers_count(self.ctx)
end

-- Returns the ith key in the list of signers in the context.
---@param index integer
---@return GPGmeKey?
function Context:signer_at(index)
  local gpgme_key = M.C.gpgme_signers_enum(self.ctx, index)
  return gpgme_key ~= nil and Key.new(gpgme_key) or nil
end

-- Creates a signature for the text.
---@param plain GPGmeData
---@param sig GPGmeData
---@param mode GPGME_SIG_MODE
function Context:sign(plain, sig, mode)
  local err = M.C.gpgme_op_sign(self.ctx, plain.data, sig.data, mode)
  return gpgme_err_code(err)
end

-- Verify detach signature and text
---@param sig GPGmeData
---@param signed_text GPGmeData
function Context:verify_detach(sig, signed_text)
  local err = M.C.gpgme_op_verify(self.ctx, sig.data, signed_text.data, nil)
  return gpgme_err_code(err)
end

---@return ffi.cdata*
function Context:verify_result()
  return M.C.gpgme_op_verify_result(self.ctx)
end

-- Find key
---@param fpr string key fingerprint or id
---@param is_secret boolean get secret key or not
---@return GPGmeKey?
---@return GPGME_ERROR_CODE
function Context:get_key(fpr, is_secret)
  local key = M.types.gpgme_key_double_pointer()
  local err = M.C.gpgme_get_key(self.ctx, fpr, key, is_secret and 1 or 0)
  if err ~= 0 then
    return nil, gpgme_err_code(err)
  end

  return Key.new(key[0]), 0
end

-- ======================
-- | GPGme data methods |
-- ======================

-- Inits new GPGme data
---@param gpgme_data ffi.cdata* gpgme_data pointer, own data
---@return GPGmeData
function Data.new(gpgme_data)
  local data = { data = M.types.gpgme_data_pointer(gpgme_data) }
  setmetatable(data, Data)

  ffi.gc(data.data, M.C.gpgme_data_release)
  return data
end

-- Changes the current read/write position.
---@param offset integer Offset
---@param whence integer how the offset should be interpreted.
---@return integer
function Data:seek(offset, whence)
  local err = M.C.gpgme_data_seek(self.data, offset, whence)
  return err
end

-- Rewind read/write positions.
function Data:rewind()
  return M.C.gpgme_data_seek(self.data, 0, 0)
end

-- Read data from GPGme Data.
---@paran length integer
---@return string? buffer
function Data:read(length)
  local buffer = char_array(length)
  local read = M.C.gpgme_data_read(self.data, buffer, length)

  if read < 0 then
    return nil
  end
  return ffi.string(buffer, read)
end

-- ======================
-- | GPGme key methods |
-- ======================

-- Inits new GPGme key
---@param gpgme_key ffi.cdata* gpgme_key_t, own data
---@return GPGmeKey
function Key.new(gpgme_key)
  local key = { key = M.types.gpgme_key_pointer(gpgme_key) }
  setmetatable(key, Key)

  ffi.gc(key.key, M.C.gpgme_key_unref)
  return key
end

-- ===================
-- | GPGme Functions |
-- ===================

-- Translates error code to string
---@param err_code integer
---@return string
function M.error_string(err_code)
  return ffi.string(M.C.gpgme_strerror(err_code))
end

-- Creates new GPGme context
---@return GPGmeContext?
---@return GPGME_ERROR_CODE err gpgpme_err_code
function M.new_context()
  local ctx = M.types.gpgme_ctx_double_pointer()
  local err = M.C.gpgme_new(ctx)
  if err ~= 0 then
    return nil, gpgme_err_code(err)
  end

  return Context.new(ctx[0]), 0
end

-- Creates new GPGme data from string.
---@param buf string buffer content
---@param copy boolean copy buffer data or not
---@return GPGmeData?
---@return GPGME_ERROR_CODE err gpgpme_err_code
function M.new_data_from_string(buf, copy)
  local data = M.types.gpgme_data_double_pointer()
  local err = M.C.gpgme_data_new_from_mem(data, buf, buf:len(), copy and 1 or 0)
  if err ~= 0 then
    return nil, gpgme_err_code(err)
  end

  return Data.new(data[0]), 0
end

-- Creates new GPGmew data.
---@return GPGmeData?
---@return GPGME_ERROR_CODE err gpgme_err_code
function M.new_data()
  local data = M.types.gpgme_data_double_pointer()
  local err = M.C.gpgme_data_new(data)
  if err ~= 0 then
    return nil, gpgme_err_code(err)
  end

  return Data.new(data[0]), 0
end

---@param ctx GPGmeContext? GPGme context, if nil, create new context
---@param content string content to sign
---@return string? signed signed data
---@return GPGME_ERROR_CODE err error code
function M.sign_string_detach(ctx, content)
  local err
  local ctx_ = ctx
  if not ctx_ then
    ctx_, err = M.new_context()
    if not ctx_ then
      return nil, err
    end
    ctx_:set_amor(true)
  end

  local content_data, signed_data
  content_data, err = M.new_data_from_string(content, false)
  if not content_data then
    return nil, err
  end

  signed_data, err = M.new_data()
  if not signed_data then
    return nil, err
  end

  err = ctx_:sign(content_data, signed_data, M.GPGME_SIG_MODE.DETACH)
  if err ~= 0 then
    return nil, err
  end

  signed_data:rewind()
  return signed_data:read(1024), 0
end

-- Verified signed text with a detach sig
---@param ctx GPGmeContext? GPGme context, if nil, create new one
---@param sig string signature
---@param signed string signed text
---@return GPGME_ERROR_CODE? status
---@return GPGME_ERROR_CODE
function M.verify_detach(ctx, sig, signed)
  local err
  local ctx_ = ctx
  if not ctx_ then
    ctx_, err = M.new_context()
    if not ctx_ then
      return nil, err
    end
    ctx_:set_amor(true)
  end

  local sig_data, signed_data
  sig_data, err = M.new_data_from_string(sig, false)
  if not sig_data then
    return nil, err
  end

  signed_data, err = M.new_data_from_string(signed, false)
  if not signed_data then
    return nil, err
  end

  err = ctx_:verify_detach(sig_data, signed_data)
  if err ~= 0 then
    return nil, err
  end

  local result = ctx_:verify_result()
  if result ~= nil and result["signatures"] ~= nil then
    local signatures = result["signatures"]
    return gpgme_err_code(signatures["status"]), 0
  end

  return nil, 0
end

return M
