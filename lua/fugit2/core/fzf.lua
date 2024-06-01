-- Port fzf algorithm to lua
-- Refer https://github.com/junegunn/fzf/blob/master/src/algo/algo.go

local Path = require "plenary.path"
local ffi = require "ffi"
local table_clear = require "table.clear"
local table_new = require "table.new"

local Matrix = require "fugit2.core.matrix"

local M = {}

---@class FuzzyMatchResult
---@field start integer?
---@field stop integer?
---@field score integer

---@class FuzzyMatchSlab
---@field ui8 ffi.cdata* unsigned char array
---@field ui8_size integer i8 allocated size
---@field i16 ffi.cdata* int16 array
---@field i16_size integer i16 allocated size
---@field ui32 ffi.cdata* unsigned int32 array
---@field ui32_size integer ui32 allocated size

---@enum FuzzyCharClass
local CHAR_CLASS = {
  WHITE = 0,
  NON_WORD = 1,
  DELIMITER = 2,
  LOWER = 3,
  UPPER = 4,
  LETTER = 5,
  NUMBER = 6,
}

local SCORE = {
  SCORE_MATCH = 16,
  SCORE_GAP_START = -3,
  SCORE_GAP_EXTENSION = -1,
  BONUS_BOUNDARY = 8,
  BONUS_NON_WORD = 8,
  BONUS_CAMEL_123 = 7,
  BONUS_CONSECUTIVE = 3 + 1,
  BONUS_BOUNDARY_WHITE = 8 + 2,
  BONUS_BOUNDARY_DELIMITER = 8 + 1,
  BONUS_FIRST_CHAR_MULTIPLIER = 2,
}

local WHITE_CHARS = { 32, 9, 10, 11, 12, 13, 133, 160 } -- " \t\n\v\f\r\x85\xA0"
local DELIMITER_CHARS = { 47, 44, 58, 59, 124 } -- "/,:;|"

local char_array = ffi.typeof "const unsigned char*"
local int16_array = ffi.typeof "int16_t[?]"
local uint32_array = ffi.typeof "uint32_t[?]"

---@param prev_class FuzzyCharClass
---@param class FuzzyCharClass
---@return integer
function M.bonus_for(prev_class, class)
  if class > CHAR_CLASS.NON_WORD then
    if prev_class == CHAR_CLASS.WHITE then
      -- Word boundary after whitespace
      return SCORE.BONUS_BOUNDARY_WHITE
    elseif prev_class == CHAR_CLASS.DELIMITER then
      return SCORE.BONUS_BOUNDARY_DELIMITER
    elseif prev_class == CHAR_CLASS.NON_WORD then
      return SCORE.BONUS_BOUNDARY
    end
  end

  if
    prev_class == CHAR_CLASS.LOWER and class == CHAR_CLASS.UPPER
    or prev_class ~= CHAR_CLASS.NUMBER and class == CHAR_CLASS.NUMBER
  then
    -- camelCase letter123
    return SCORE.BONUS_CAMEL_123
  end

  if class == CHAR_CLASS.NON_WORD or class == CHAR_CLASS.DELIMITER then
    return SCORE.BONUS_NON_WORD
  elseif class == CHAR_CLASS.WHITE then
    return SCORE.BONUS_BOUNDARY_WHITE
  end

  return 0
end

-- Inits fuzzy match module
---@param scheme "default"|"path"|"history"
function M.init(scheme)
  M.INITIAL_CHAR_CLASS = CHAR_CLASS.WHITE

  if scheme == "default" then
    SCORE.BONUS_BOUNDARY_WHITE = SCORE.BONUS_BOUNDARY + 2
    SCORE.BONUS_BOUNDARY_DELIMITER = SCORE.BONUS_BOUNDARY + 1
  elseif scheme == "path" then
    SCORE.BONUS_BOUNDARY_WHITE = SCORE.BONUS_BOUNDARY
    SCORE.BONUS_BOUNDARY_DELIMITER = SCORE.BONUS_BOUNDARY + 1
    M.INITIAL_CHAR_CLASS = CHAR_CLASS.DELIMITER

    table_clear(DELIMITER_CHARS)
    if Path.path.sep == "/" then
      DELIMITER_CHARS[1] = 47
    else
      DELIMITER_CHARS[1] = string.byte(Path.path.sep)
      DELIMITER_CHARS[2] = 47
    end
  elseif scheme == "history" then
    SCORE.BONUS_BOUNDARY_WHITE = SCORE.BONUS_BOUNDARY
    SCORE.BONUS_BOUNDARY_DELIMITER = SCORE.BONUS_BOUNDARY
  end

  local matrix = Matrix.new_int16(8, 8) -- use 8x8 matrix for better aligned

  -- init bonus matrix
  for i = 0, 6 do
    local idx = i * 8
    for j = 0, 6 do
      matrix.matrix[idx + j] = M.bonus_for(i, j)
    end
  end

  M.BONUS_MATRIX = matrix
end

---@param c integer character as byte
local function ascii_char_class(c)
  if c >= 48 and c <= 57 then -- in [0-9]
    return CHAR_CLASS.NUMBER
  elseif c >= 65 and c <= 90 then -- in [A-Z]
    return CHAR_CLASS.UPPER
  elseif c >= 97 and c <= 122 then -- in [a-z]
    return CHAR_CLASS.LOWER
  elseif vim.tbl_contains(WHITE_CHARS, c) then
    return CHAR_CLASS.WHITE
  elseif vim.tbl_contains(DELIMITER_CHARS, c) then
    return CHAR_CLASS.DELIMITER
  end
  return CHAR_CLASS.NON_WORD
end

---@param input string
---@param case_sensitive boolean
---@param b integer
---@param from integer 0-th based index
---@return integer? skip_idx 0-th based index
local function try_skip(input, case_sensitive, b, from)
  local b_char = string.char(b)
  local idx, _ = input:find(b_char, from + 1, true)
  if idx == from + 1 then
    -- Can't skip any further
    return from
  end

  -- We may need to search for the uppercase letter again.
  if not case_sensitive and b >= 97 and b <= 122 then
    local find_str = input
    if idx then
      find_str = input:sub(1, idx - 1)
    end
    local insensitive_idx, _ = find_str:find(string.upper(b_char), from + 1, true)
    if insensitive_idx then
      idx = insensitive_idx
    end
  end

  return idx and idx - 1 or nil
end

---@param chr ffi.cdata*
---@param n integer
local function is_ascii(chr, n)
  for i = 0, n - 1 do
    if chr[i] > 127 then
      return false
    end
  end
  return true
end

---@param buf string
function M.is_ascii(buf)
  local ptr = ffi.cast(char_array, buf)
  return is_ascii(ptr, buf:len())
end

---@param input string
---@param pattern string
---@return integer? min_idx 1-th based index
---@return integer? max_idx 1-th based index, inclusive
local function ascii_fuzzy_index(input, pattern, case_sensitive)
  local pattern_ptr = ffi.cast(char_array, pattern)

  if not is_ascii(pattern_ptr, pattern:len()) then
    return nil, nil
  end

  local b, idx
  local first_idx, last_idx = 0, 0
  idx = 0
  for pidx = 0, pattern:len() - 1 do
    b = pattern_ptr[pidx]
    idx = try_skip(input, case_sensitive, b, idx)
    if not idx then
      return nil, nil
    end
    if pidx == 0 and idx > 0 then
      -- Step back to find the right bonus point
      first_idx = idx - 1
    end
    last_idx = idx
    idx = idx + 1
  end

  -- Find the last appearance of the last character of the pattern to limit the search scope
  local input_ptr = ffi.cast(char_array, input)
  if not case_sensitive and b >= 97 and b <= 122 then
    local bu = b - 32
    for i = input:len() - 1, last_idx + 1, -1 do
      if input_ptr[i] == b or input_ptr[i] == bu then
        return first_idx + 1, i + 1
      end
    end
  else
    for i = input:len() - 1, last_idx + 1, -1 do
      if input_ptr[i] == b then
        return first_idx + 1, i + 1
      end
    end
  end

  return first_idx + 1, last_idx + 1
end

---@param index integer
---@param max integer
---@param forward boolean
---@return integer 0-th based index
local function index_at(index, max, forward)
  return forward and index or max - index - 1
end

---@param with_pos boolean
---@param len integer
---@return integer[]?
local function pos_array(with_pos, len)
  if with_pos then
    return table_new(len, 0)
  end
  return nil
end

--==================
--| Fuzzy Match V1 |
--==================

-- Implement the same sorting criteria as V2
---@param case_sensitive boolean
---@param normalize boolean Normalize unicode, not usable now
---@param input_ptr ffi.cdata*
---@param pattern_ptr ffi.cdata*
---@param pattern_len integer
---@param sidx integer 0-th based index
---@param eidx integer 0-th based index
---@param with_pos boolean
---@return integer? score
---@return integer[]? match indices
local function calculate_score(case_sensitive, normalize, input_ptr, pattern_ptr, pattern_len, sidx, eidx, with_pos)
  local pidx, score, in_gap, consecutive, first_bonus = 0, 0, false, 0, 0
  local pos = pos_array(with_pos, pattern_len)
  local prev_class = M.INITIAL_CHAR_CLASS

  if sidx > 0 then
    prev_class = ascii_char_class(input_ptr[sidx - 1])
  end

  for i = sidx, eidx - 1 do
    local char = input_ptr[i]
    local char_cls = ascii_char_class(char)

    if not case_sensitive and char >= 65 and char <= 90 then
      char = char + 32
    end

    if char == pattern_ptr[pidx] then
      if with_pos and pos then
        pos[#pos + 1] = i + 1 -- org: i
      end

      score = score + SCORE.SCORE_MATCH
      local bonus = M.BONUS_MATRIX:at(prev_class, char_cls)

      if consecutive == 0 then
        first_bonus = bonus
      else
        -- Break consecutive chunk
        if bonus >= SCORE.BONUS_BOUNDARY and bonus > first_bonus then
          first_bonus = bonus
        end
        bonus = math.max(bonus, first_bonus, SCORE.BONUS_CONSECUTIVE)
      end

      if pidx == 0 then
        score = score + bonus * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      else
        score = score + bonus
      end
      in_gap = false
      consecutive = consecutive + 1
      pidx = pidx + 1
    else
      if in_gap then
        score = score + SCORE.SCORE_GAP_EXTENSION
      else
        score = score + SCORE.SCORE_GAP_START
      end
      in_gap = true
      consecutive = 0
      first_bonus = 0
    end

    prev_class = char_cls
  end

  return score, pos
end

-- Fuzzy match v1 algo
---@param case_sensitive boolean
---@param normalize boolean Normalize unicode, not usable now
---@param forward boolean
---@param input string
---@param pattern string
---@param with_pos boolean
---@param slab FuzzyMatchSlab? no used in v1
---@return FuzzyMatchResult
---@return integer[]? match indices
function M.fuzzy_match_v1(case_sensitive, normalize, forward, input, pattern, with_pos, slab)
  if pattern:len() == 0 then
    return { start = 1, stop = 1, 0 }, nil
  end
  local idx, _ = ascii_fuzzy_index(input, pattern, case_sensitive)
  if not idx then
    return { score = 0 }, nil
  end

  local pidx = 0
  local sidx, eidx

  local len_input = input:len()
  local len_pattern = pattern:len()

  local input_ptr = ffi.cast(char_array, input)
  local pattern_ptr = ffi.cast(char_array, pattern)

  for i = 0, len_input - 1 do
    local char = input_ptr[index_at(i, len_input, forward)]

    if not case_sensitive and char >= 65 and char <= 90 then
      char = char + 32
    end

    local pchar = pattern_ptr[index_at(pidx, len_pattern, forward)]
    if char == pchar then
      if not sidx then
        sidx = i
      end

      pidx = pidx + 1
      if pidx == len_pattern then
        eidx = i + 1
        break
      end
    end
  end

  if sidx and eidx then
    pidx = pidx - 1

    for i = eidx - 1, sidx, -1 do
      local char = input_ptr[index_at(i, len_input, forward)]

      if not case_sensitive and char >= 65 and char <= 90 then
        char = char + 32
      end

      local pchar = pattern_ptr[index_at(pidx, len_pattern, forward)]
      if char == pchar then
        pidx = pidx - 1
        if pidx < 0 then
          sidx = i
          break
        end
      end
    end

    if not forward then
      sidx, eidx = len_input - eidx, len_input - sidx
    end

    local score, pos =
      calculate_score(case_sensitive, normalize, input_ptr, pattern_ptr, len_pattern, sidx, eidx, with_pos)
    return { start = sidx + 1, stop = eidx, score = score }, pos
  end

  return { score = 0 }, nil
end

--==================
--| Fuzzy Match V2 |
--==================

---@param offset integer offset in slab
---@param slab FuzzyMatchSlab?
---@param size integer request size
---@return integer offset offset after allocated
---@return ffi.cdata* c_data array
local function alloc8(offset, slab, size)
  if slab and slab.ui8_size > offset + size then
    return offset + size, slab.ui8 + offset
  end
  return offset, ffi.new("uint8_t[?]", size)
end

---@param offset integer offset in slab
---@param slab FuzzyMatchSlab?
---@param size integer request size
---@return integer offset offset after allocated
---@return ffi.cdata* c_data array
local function alloc16(offset, slab, size)
  if slab and slab.i16_size > offset + size then
    return offset + size, slab.i16 + offset
  end
  return offset, ffi.new(int16_array, size)
end

---@param offset integer offset in slab
---@param slab FuzzyMatchSlab?
---@param size integer request size
---@return integer offset offset after allocated
---@return ffi.cdata* c_data array
local function alloc32(offset, slab, size)
  if slab and slab.ui32_size > offset + size then
    return offset + size, slab.ui32 + offset
  end
  return offset, ffi.new(uint32_array, size)
end

-- Fuzzy match v2 algo
---@param case_sensitive boolean
---@param normalize boolean Normalize unicode, not usable now
---@param forward boolean
---@param input string
---@param pattern string
---@param with_pos boolean
---@param slab FuzzyMatchSlab?
---@return FuzzyMatchResult
---@return integer[]? match indices
function M.fuzzy_match_v2(case_sensitive, normalize, forward, input, pattern, with_pos, slab)
  -- Assume that pattern is given in lowercase if case-insensitive.
  -- First check if there's a match and calculate bonus for each position.
  -- If the input string is too long, consider finding the matching chars in
  -- this phase as well (non-optimal alignment).
  local m = pattern:len()
  if m == 0 then
    return { start = 1, stop = 1, score = 0 }, with_pos and {} or nil
  end

  local N = input:len()
  if m > N then
    return { score = 0 }, nil
  end

  -- Since O(nm) algorithm can be prohibitively expensive for large input,
  -- we fall back to the greedy algorithm.
  if slab ~= nil and N * m > slab.i16_size then
    return M.fuzzy_match_v1(case_sensitive, normalize, forward, input, pattern, with_pos, slab)
  end

  -- phase 1: Optimized search for ASCII string
  local min_idx, max_idx = ascii_fuzzy_index(input, pattern, case_sensitive)
  if not min_idx or not max_idx then
    return { score = 0 }, nil
  end

  N = max_idx - min_idx + 1

  -- phase 2: Calculate bonus for each point

  -- Reuse pre-allocated integer slice to avoid unnecessary sweeping of garbages
  local offset16, offset32 = 0, 0
  local H0, C0, B, F
  offset16, H0 = alloc16(offset16, slab, N)
  offset16, C0 = alloc16(offset16, slab, N)
  -- Bonus point for each position
  offset16, B = alloc16(offset16, slab, N)
  -- The first occurrence of each character in the pattern
  offset32, F = alloc32(offset32, slab, m)
  -- Rune array
  local input_t = input:sub(min_idx, max_idx)
  local T = ffi.cast(char_array, input_t)
  -- pattern aray
  local pattern_ptr = ffi.cast(char_array, pattern)

  local bonus_matrix = M.BONUS_MATRIX

  local max_score, max_score_pos = 0, 0
  local pidx, last_idx = 0, 0
  local prev_cls = M.INITIAL_CHAR_CLASS
  local prev_H0 = 0
  local pchar0, pchar = pattern_ptr[0], pattern_ptr[0]
  local in_gap = false

  for i = 0, input_t:len() - 1 do
    local char = T[i]
    local char_cls = ascii_char_class(char)

    if not case_sensitive and char_cls == CHAR_CLASS.UPPER then
      char = char + 32
    end

    local bonus = bonus_matrix:at(prev_cls, char_cls)
    B[i] = bonus
    prev_cls = char_cls

    if char == pchar then
      if pidx < m then
        F[pidx] = i
        pidx = pidx + 1
        pchar = pattern_ptr[math.min(pidx, m - 1)]
      end
      last_idx = i
    end

    if char == pchar0 then
      local score = SCORE.SCORE_MATCH + bonus * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      H0[i] = score
      C0[i] = 1
      if m == 1 and (forward and score > max_score or not forward and score >= max_score) then
        max_score, max_score_pos = score, i
        if forward and bonus >= SCORE.BONUS_BOUNDARY then
          break
        end
      end
      in_gap = false
    else
      if in_gap then
        H0[i] = math.max(prev_H0 + SCORE.SCORE_GAP_EXTENSION, 0)
      else
        H0[i] = math.max(prev_H0 + SCORE.SCORE_GAP_START, 0)
      end
      C0[i] = 0
      in_gap = true
    end

    prev_H0 = H0[i]
  end

  if pidx ~= m then
    return { score = 0 }, nil
  end

  if m == 1 then
    local result = {
      start = min_idx + max_score_pos,
      stop = min_idx + max_score_pos,
      score = max_score,
    }
    if not with_pos then
      return result, nil
    end
    local pos = { min_idx + max_score_pos }
    return result, pos
  end

  -- phase 3: Fill in score matrix (H)
  -- Unlike the original algorithm, we do not allow omission.
  local f0 = F[0]
  local width = last_idx - f0 + 1
  local H
  offset16, H = alloc16(offset16, slab, width * m)
  for i = f0, last_idx do
    H[i - f0] = H0[i]
  end
  for i = width, width * m - 1 do
    H[i] = 0
  end

  -- Possible length of consecutive chunk at each position.
  local _, C = alloc16(offset16, slab, width * m)
  for i = f0, last_idx do
    C[i - f0] = C0[i]
  end
  for i = width, width * m - 1 do
    C[i] = 0
  end

  if not case_sensitive then
    input_t = input_t:lower()
    T = ffi.cast(char_array, input_t)
  end

  for i = 1, m - 1 do
    local f = F[i]
    pchar = pattern_ptr[i]
    local row = i * width
    in_gap = false

    local idx_sub = row - f0
    local idx_left = idx_sub - 1
    local idx_diag = idx_left - width

    H[idx_left + f] = 0

    for j = f, last_idx do
      local char = T[j]
      local col = j
      local s1, s2, consecutive = 0, 0, 0

      if in_gap then
        s2 = H[idx_left + j] + SCORE.SCORE_GAP_EXTENSION
      else
        s2 = H[idx_left + j] + SCORE.SCORE_GAP_START
      end

      if pchar == char then
        s1 = H[idx_diag + j] + SCORE.SCORE_MATCH
        local b = B[j]
        consecutive = C[idx_diag + j] + 1
        if consecutive > 1 then
          local fb = B[col - consecutive + 1]
          -- Break consecutive chunk
          if b >= SCORE.BONUS_BOUNDARY and b > fb then
            consecutive = 1
          else
            b = math.max(b, SCORE.BONUS_CONSECUTIVE, fb)
          end
        end

        if s1 + b < s2 then
          s1 = s1 + B[j]
          consecutive = 0
        else
          s1 = s1 + b
        end
      end

      C[idx_sub + j] = consecutive

      in_gap = s1 < s2
      local score = math.max(s1, s2, 0)
      if i == m - 1 and (forward and score > max_score or not forward and score >= max_score) then
        max_score, max_score_pos = score, col
      end
      H[idx_sub + j] = score
    end
  end

  -- phase 4: (Optional) Backtrace to find character positions
  local pos = pos_array(with_pos, m)
  local j = f0
  if with_pos then
    local i = m - 1
    j = max_score_pos
    local prefer_match = true

    while true do
      local I = i * width
      local j0 = j - f0
      local s = H[I + j0]

      local s1, s2 = 0, 0
      if i > 0 and j >= F[i] then
        s1 = H[I - width + j0 - 1]
      end
      if j > F[i] then
        s2 = H[I + j0 - 1]
      end

      if s > s1 and (s > s2 or s == s2 and prefer_match) then
        pos[i + 1] = j + min_idx
        if i == 0 then
          break
        end
        i = i - 1
      end

      prefer_match = C[I + j0] > 1 or I + width + j0 + 1 < width * m and C[I + width + j0 + 1] > 0
      j = j - 1
    end
  end

  -- Start offset we return here is only relevant when begin tiebreak is used.
  -- However finding the accurate offset requires backtracking, and we don't
  -- want to pay extra cost for the option that has lost its importance.
  return {
    start = min_idx + j, -- org: min_idx + j
    stop = min_idx + max_score_pos, -- org: min_idx + max_score_pos
    score = max_score,
  },
    pos
end

---@param size_16 integer
---@param size_32 integer
---@return FuzzyMatchSlab
function M.new_slab(size_16, size_32)
  return {
    i16 = ffi.new(int16_array, size_16),
    i16_size = size_16,
    ui32 = ffi.new(uint32_array, size_32),
    ui32_size = size_32,
  }
end

M.SCORE = SCORE

return M
