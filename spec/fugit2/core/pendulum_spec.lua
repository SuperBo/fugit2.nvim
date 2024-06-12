-- Test pendulum module

local pendulum = require "fugit2.core.pendulum"

---@param diff PreciseDiff
---@param years integer?
---@param months integer?
---@param days integer?
---@param hours integer?
---@param minutes integer?
---@param seconds integer?
local function assert_diff(diff, years, months, days, hours, minutes, seconds)
  assert.are.equal(years or 0, diff.years)
  assert.are.equal(months or 0, diff.months)
  assert.are.equal(days or 0, diff.days)
  assert.are.equal(hours or 0, diff.hours)
  assert.are.equal(minutes or 0, diff.minutes)
  assert.are.equal(seconds or 0, diff.seconds)
end

describe("pendulum", function()
  setup(function()
    pendulum.init()
  end)

  it("detects leap year", function()
    local leap_years = { 1964, 1976, 2024, 2028, 2048, 2280 }
    local non_leap_years = { 1900, 2100, 2200, 2021, 2023, 1987, 2115 }

    for _, year in ipairs(leap_years) do
      assert.is_true(pendulum.is_leap_year(year))
    end

    for _, year in ipairs(non_leap_years) do
      assert.is_false(pendulum.is_leap_year(year))
    end
  end)

  it("inits correct days in month in normal year", function()
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

    for i, num_days in ipairs(days) do
      assert.are.equal(num_days, pendulum.DAYS_PER_MONTHS:at(0, i - 1))
    end
  end)

  it("inits correct days in month in leap year", function()
    local days = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

    for i, num_days in ipairs(days) do
      assert.are.equal(num_days, pendulum.DAYS_PER_MONTHS:at(1, i - 1))
    end
  end)

  it("calculates precise diff", function()
    local dt1 = pendulum.datetime(2003, 3, 1, 0, 0, 0)
    local dt2 = pendulum.datetime(2003, 1, 31, 23, 59, 59)

    local diff1 = pendulum.precise_diff(dt1, dt2)
    local diff2 = pendulum.precise_diff(dt2, dt1)

    assert_diff(diff1, 0, 1, 0, 0, 0, 1)
    assert_diff(diff2, 0, -1, 0, 0, 0, -1)
  end)

  it("calculates precise diff 2", function()
    local dt1 = pendulum.datetime(2012, 3, 1, 0, 0, 0)
    local dt2 = pendulum.datetime(2012, 1, 31, 23, 59, 59)

    local diff1 = pendulum.precise_diff(dt1, dt2)
    local diff2 = pendulum.precise_diff(dt2, dt1)

    assert_diff(diff1, 0, 1, 0, 0, 0, 1)
    assert.are.equal(30, diff1.total_days)
    assert_diff(diff2, 0, -1, 0, 0, 0, -1)
    assert.are.equal(-30, diff2.total_days)
  end)

  it("calculates precise diff 3", function()
    local dt1 = pendulum.datetime(2001, 1, 1)
    local dt2 = pendulum.datetime(2003, 9, 17, 20, 54, 47)

    local diff = pendulum.precise_diff(dt2, dt1)

    assert_diff(diff, 2, 8, 16, 20, 54, 47)
  end)

  it("calculates precise diff 1 year", function()
    local dt1 = pendulum.datetime(2017, 2, 17, 16, 5, 45)
    local dt2 = pendulum.datetime(2018, 2, 17, 16, 5, 45)

    local diff = pendulum.precise_diff(dt2, dt1)
    assert_diff(diff, 1, 0, 0, 0, 0, 0)
  end)

  it("converts datetime to string in abbreviated format", function()
    local dt1 = pendulum.datetime(2024, 10, 1)
    local dt2 = pendulum.datetime(2022, 9, 5)
    local dt3 = pendulum.datetime(2023, 12, 8)
    local dt4 = pendulum.datetime(2018, 7, 30)

    assert.are.equal("Oct 1, 2024", pendulum.datetime_tostring(dt1, true))
    assert.are.equal("Sep 5, 2022", pendulum.datetime_tostring(dt2, true))
    assert.are.equal("Dec 8, 2023", pendulum.datetime_tostring(dt3, true))
    assert.are.equal("Jul 30, 2018", pendulum.datetime_tostring(dt4, true))
  end)

  it("converts datetime to string in iso format", function()
    local dt1 = pendulum.datetime(2024, 10, 15)
    local dt2 = pendulum.datetime(2022, 9, 5)
    local dt3 = pendulum.datetime(2023, 12, 8)
    local dt4 = pendulum.datetime(2018, 3, 30)

    assert.are.equal("2024-10-15", pendulum.datetime_tostring(dt1))
    assert.are.equal("2022-09-05", pendulum.datetime_tostring(dt2))
    assert.are.equal("2023-12-08", pendulum.datetime_tostring(dt3, false))
    assert.are.equal("2018-03-30", pendulum.datetime_tostring(dt4, false))
  end)
end)
