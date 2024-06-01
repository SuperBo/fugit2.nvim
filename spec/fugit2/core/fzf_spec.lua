-- Test fzf algorithm module

local fzf = require "fugit2.core.fzf"
local SCORE = fzf.SCORE

describe("is_ascii", function()
  it("return true for ascii string", function()
    assert.is_true(fzf.is_ascii "")
    assert.is_true(fzf.is_ascii "Hello World!")
  end)

  it("return false for unicode string", function()
    assert.is_false(fzf.is_ascii "Unicode Xin chào")
    assert.is_false(fzf.is_ascii "official name 简化字")
    assert.is_false(fzf.is_ascii "Le restaurant italien s’ouvre à midi.")
  end)
end)

describe("bonus_for", function()
  setup(function()
    fzf.init "default"
  end)

  it("return correct bonus", function()
    assert.are.equal(10, fzf.bonus_for(0, 3))
    assert.are.equal(0, fzf.bonus_for(3, 3))
    assert.are.equal(7, fzf.bonus_for(3, 4))
    assert.are.equal(0, fzf.bonus_for(4, 3))
    assert.are.equal(0, fzf.bonus_for(4, 4))
  end)

  it("init correct bonus matrix", function()
    assert.are.equal(10, fzf.BONUS_MATRIX:at(0, 3))
    assert.are.equal(0, fzf.BONUS_MATRIX:at(3, 3))
    assert.are.equal(7, fzf.BONUS_MATRIX:at(3, 4))
    assert.are.equal(0, fzf.BONUS_MATRIX:at(4, 3))
    assert.are.equal(0, fzf.BONUS_MATRIX:at(4, 4))
  end)
end)

local function assert_match2(match_fn, case_sensitive, normalize, forward, input, pattern, sidx, eidx, score)
  if not case_sensitive then
    pattern = pattern:lower()
  end

  local res, pos = match_fn(case_sensitive, normalize, forward, input, pattern, true, nil)

  if pos ~= nil and #pos > 0 then
    local start = pos[1]
    local stop = pos[#pos]

    assert.equals(pattern:len(), #pos)
    assert.equals(sidx, start)
    assert.equals(eidx, stop)
  end

  assert.equals(sidx, res.start)
  assert.equals(eidx, res.stop)
  assert.equals(score, res.score)
end

local function assert_match(match_fn, case_sensitive, forward, input, pattern, sidx, eidx, score)
  assert_match2(match_fn, case_sensitive, false, forward, input, pattern, sidx, eidx, score)
end

local function fuzzy_match_suite(fn, forward)
  assert_match(
    fn,
    false,
    forward,
    "fooBarbaz1",
    "oBZ",
    3,
    9,
    SCORE.SCORE_MATCH * 3 + SCORE.BONUS_CAMEL_123 + SCORE.SCORE_GAP_START + SCORE.SCORE_GAP_EXTENSION * 3
  )

  assert_match(
    fn,
    false,
    forward,
    "foo bar baz",
    "fbb",
    1,
    9,
    SCORE.SCORE_MATCH * 3
      + SCORE.BONUS_BOUNDARY_WHITE * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_BOUNDARY_WHITE * 2
      + 2 * SCORE.SCORE_GAP_START
      + 4 * SCORE.SCORE_GAP_EXTENSION
  )

  assert_match(
    fn,
    false,
    forward,
    "/AutomatorDocument.icns",
    "rdoc",
    10,
    13,
    SCORE.SCORE_MATCH * 4 + SCORE.BONUS_CAMEL_123 + SCORE.BONUS_CONSECUTIVE * 2
  )

  assert_match(
    fn,
    false,
    forward,
    "/man1/zshcompctl.1",
    "zshc",
    7,
    10,
    SCORE.SCORE_MATCH * 4
      + SCORE.BONUS_BOUNDARY_DELIMITER * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_BOUNDARY_DELIMITER * 3
  )

  assert_match(
    fn,
    false,
    forward,
    "/.oh-my-zsh/cache",
    "zshc",
    9,
    13,
    SCORE.SCORE_MATCH * 4
      + SCORE.BONUS_BOUNDARY * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_BOUNDARY * 2
      + SCORE.SCORE_GAP_START
      + SCORE.BONUS_BOUNDARY_DELIMITER
  )

  assert_match(
    fn,
    false,
    forward,
    "ab0123 456",
    "12356",
    4,
    10,
    SCORE.SCORE_MATCH * 5 + SCORE.BONUS_CONSECUTIVE * 3 + SCORE.SCORE_GAP_START + SCORE.SCORE_GAP_EXTENSION
  )

  assert_match(
    fn,
    false,
    forward,
    "abc123 456",
    "12356",
    4,
    10,
    SCORE.SCORE_MATCH * 5
      + SCORE.BONUS_CAMEL_123 * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_CAMEL_123 * 2
      + SCORE.BONUS_CONSECUTIVE
      + SCORE.SCORE_GAP_START
      + SCORE.SCORE_GAP_EXTENSION
  )

  assert_match(
    fn,
    false,
    forward,
    "foo/bar/baz",
    "fbb",
    1,
    9,
    SCORE.SCORE_MATCH * 3
      + SCORE.BONUS_BOUNDARY_WHITE * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_BOUNDARY_DELIMITER * 2
      + 2 * SCORE.SCORE_GAP_START
      + 4 * SCORE.SCORE_GAP_EXTENSION
  )

  assert_match(
    fn,
    false,
    forward,
    "fooBarBaz",
    "fbb",
    1,
    7,
    SCORE.SCORE_MATCH * 3
      + SCORE.BONUS_BOUNDARY_WHITE * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_CAMEL_123 * 2
      + SCORE.SCORE_GAP_START * 2
      + SCORE.SCORE_GAP_EXTENSION * 2
  )

  assert_match(
    fn,
    false,
    forward,
    "foo barbaz",
    "fbb",
    1,
    8,
    SCORE.SCORE_MATCH * 3
      + SCORE.BONUS_BOUNDARY_WHITE * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_BOUNDARY_WHITE
      + SCORE.SCORE_GAP_START * 2
      + SCORE.SCORE_GAP_EXTENSION * 3
  )

  assert_match(
    fn,
    false,
    forward,
    "fooBar Baz",
    "foob",
    1,
    4,
    SCORE.SCORE_MATCH * 4
      + SCORE.BONUS_BOUNDARY_WHITE * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_BOUNDARY_WHITE * 3
  )

  assert_match(
    fn,
    false,
    forward,
    "xFoo-Bar Baz",
    "foo-b",
    2,
    6,
    SCORE.SCORE_MATCH * 5
      + SCORE.BONUS_CAMEL_123 * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_CAMEL_123 * 2
      + SCORE.BONUS_NON_WORD
      + SCORE.BONUS_BOUNDARY
  )

  assert_match(
    fn,
    true,
    forward,
    "fooBarbaz",
    "oBz",
    3,
    9,
    SCORE.SCORE_MATCH * 3 + SCORE.BONUS_CAMEL_123 + SCORE.SCORE_GAP_START + SCORE.SCORE_GAP_EXTENSION * 3
  )

  assert_match(
    fn,
    true,
    forward,
    "Foo/Bar/Baz",
    "FBB",
    1,
    9,
    SCORE.SCORE_MATCH * 3
      + SCORE.BONUS_BOUNDARY_WHITE * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_BOUNDARY_DELIMITER * 2
      + SCORE.SCORE_GAP_START * 2
      + SCORE.SCORE_GAP_EXTENSION * 4
  )

  assert_match(
    fn,
    true,
    forward,
    "FooBarBaz",
    "FBB",
    1,
    7,
    SCORE.SCORE_MATCH * 3
      + SCORE.BONUS_BOUNDARY_WHITE * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_CAMEL_123 * 2
      + SCORE.SCORE_GAP_START * 2
      + SCORE.SCORE_GAP_EXTENSION * 2
  )

  assert_match(
    fn,
    true,
    forward,
    "FooBar Baz",
    "FooB",
    1,
    4,
    SCORE.SCORE_MATCH * 4
      + SCORE.BONUS_BOUNDARY_WHITE * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
      + SCORE.BONUS_BOUNDARY_WHITE * 2
      + math.max(SCORE.BONUS_CAMEL_123, SCORE.BONUS_BOUNDARY_WHITE)
  )

  assert_match(fn, true, forward, "foo-bar", "o-ba", 3, 6, SCORE.SCORE_MATCH * 4 + SCORE.BONUS_BOUNDARY * 3)

  -- no match test
  assert_match(fn, true, forward, "fooBarbaz", "oBZ", nil, nil, 0)
  assert_match(fn, true, forward, "Foo Bar Baz", "fbb", nil, nil, 0)
  assert_match(fn, true, forward, "fooBarbaz", "fooBarbazz", nil, nil, 0)
end

describe("fuzzy_match_v1", function()
  setup(function()
    fzf.init "default"
  end)

  it("match fuzzy backward", function()
    fuzzy_match_suite(fzf.fuzzy_match_v1, false)

    assert_match(
      fzf.fuzzy_match_v1,
      false,
      true,
      "foobar fb",
      "fb",
      1,
      4,
      SCORE.SCORE_MATCH * 2
        + SCORE.BONUS_BOUNDARY_WHITE * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
        + SCORE.SCORE_GAP_START
        + SCORE.SCORE_GAP_EXTENSION
    )

    assert_match(
      fzf.fuzzy_match_v1,
      false,
      false,
      "foobar fb",
      "fb",
      8,
      9,
      SCORE.SCORE_MATCH * 2
        + SCORE.BONUS_BOUNDARY_WHITE * SCORE.BONUS_FIRST_CHAR_MULTIPLIER
        + SCORE.BONUS_BOUNDARY_WHITE
    )
  end)

  it("match fuzzy forward", function()
    fuzzy_match_suite(fzf.fuzzy_match_v1, true)
  end)
end)

describe("fuzzy_match_v2", function()
  it("match fuzzy backward", function()
    fuzzy_match_suite(fzf.fuzzy_match_v2, false)
  end)

  it("match fuzzy forward", function()
    fuzzy_match_suite(fzf.fuzzy_match_v2, true)
  end)

  it("match long string", function()
    local buffer = require "string.buffer"

    local BUF_SIZE = 65536
    local buf = buffer.new(BUF_SIZE)
    local x_char = string.byte "x"
    local ptr, _ = buf:reserve(BUF_SIZE)
    for i = 0, BUF_SIZE - 2 do
      ptr[i] = x_char
    end
    ptr[BUF_SIZE - 1] = string.byte "z"
    buf:commit(BUF_SIZE)

    assert.equals(BUF_SIZE, #buf)
    assert_match(
      fzf.fuzzy_match_v2,
      true,
      true,
      buf:tostring(),
      "xz",
      BUF_SIZE - 1,
      BUF_SIZE,
      SCORE.SCORE_MATCH * 2 + SCORE.BONUS_CONSECUTIVE
    )

    buf:free()
  end)
end)
